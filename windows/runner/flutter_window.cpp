#include "flutter_window.h"

#include <optional>
#include <string>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayCallbackMessage = WM_APP + 41;
constexpr UINT kTrayOpenCommand = 42001;
constexpr UINT kTrayExitCommand = 42002;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "spartan_chat/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "show") {
      HWND window = GetHandle();
      ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
      SetForegroundWindow(window);
      NotifyVisibility(true);
      result->Success();
    } else if (call.method_name() == "flash") {
      FLASHWINFO info = {sizeof(FLASHWINFO), GetHandle(), FLASHW_TRAY, 6, 0};
      FlashWindowEx(&info);
      result->Success();
    } else result->NotImplemented();
  });

  // FENYVO screen capture protection for the application window.
  screen_security_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "fenyvo/screen_security",
          &flutter::StandardMethodCodec::GetInstance());

  screen_security_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setSecure") {
          result->NotImplemented();
          return;
        }

        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());

        if (!arguments) {
          result->Error("INVALID_ARGUMENTS", "Expected argument map");
          return;
        }

        const auto it = arguments->find(flutter::EncodableValue("enabled"));

        if (it == arguments->end()) {
          result->Error("INVALID_ARGUMENTS", "Missing enabled argument");
          return;
        }

        const auto* enabled = std::get_if<bool>(&it->second);

        if (!enabled) {
          result->Error("INVALID_ARGUMENTS", "Enabled must be boolean");
          return;
        }

        HWND hwnd = GetHandle();

        if (!hwnd || !IsWindow(hwnd)) {
          result->Error("INVALID_WINDOW", "Window is not available");
          return;
        }

        // WDA_EXCLUDEFROMCAPTURE requires Windows 10 version 2004+.
        constexpr DWORD kExcludeFromCapture = 0x00000011;
        const DWORD affinity =
            *enabled ? kExcludeFromCapture : WDA_NONE;

        if (!SetWindowDisplayAffinity(hwnd, affinity)) {
          const DWORD error = GetLastError();
          result->Error(
              "CAPTURE_PROTECTION_FAILED",
              "Windows could not change screen capture protection",
              std::to_string(error));
          return;
        }

        result->Success();
      });
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  restore_message_ = RegisterWindowMessageW(L"SPARTAN_CHAT_RESTORE_WINDOW");
  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  screen_security_channel_ = nullptr;
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (message == taskbar_created_message_) {
    tray_icon_added_ = false;
    AddTrayIcon();
    return 0;
  }
  if (message == restore_message_) {
    RestoreFromTray();
    return 0;
  }

  switch (message) {
    case WM_CLOSE:
      SavePlacement();
      if (!exiting_) {
        ShowWindow(hwnd, SW_HIDE);
        NotifyVisibility(false);
        ShowTrayHint();
        return 0;
      }
      break;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) {
        NotifyVisibility(false);
      } else if (IsWindowVisible(hwnd)) {
        NotifyVisibility(true);
      }
      break;
    case kTrayCallbackMessage:
      if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
        RestoreFromTray();
        return 0;
      }
      if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
        ShowTrayMenu();
        return 0;
      }
      break;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayOpenCommand:
          RestoreFromTray();
          return 0;
        case kTrayExitCommand:
          exiting_ = true;
          RemoveTrayIcon();
          DestroyWindow(hwnd);
          return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_ || !GetHandle()) {
    return;
  }

  tray_icon_ = {};
  tray_icon_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_.hWnd = GetHandle();
  tray_icon_.uID = 1;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_.hIcon = LoadIconW(GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(tray_icon_.szTip, L"FENYVO");

  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
  if (tray_icon_added_) {
    tray_icon_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &tray_icon_);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
  tray_icon_added_ = false;
}

void FlutterWindow::RestoreFromTray() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
  NotifyVisibility(true);
}

void FlutterWindow::NotifyVisibility(bool visible) {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(
      "visibilityChanged",
      std::make_unique<flutter::EncodableValue>(visible));
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(
      menu, MF_STRING, kTrayOpenCommand,
      L"\u041E\u0442\u043A\u0440\u044B\u0442\u044C FENYVO");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExitCommand,
              L"\u0412\u044B\u0439\u0442\u0438");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window);
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN,
                 cursor.x, cursor.y, 0, window, nullptr);
  PostMessageW(window, WM_NULL, 0, 0);
  DestroyMenu(menu);
}

void FlutterWindow::ShowTrayHint() {
  if (!tray_icon_added_ || tray_hint_shown_) {
    return;
  }
  tray_hint_shown_ = true;
  tray_icon_.uFlags = NIF_INFO;
  tray_icon_.dwInfoFlags = NIIF_INFO;
  wcscpy_s(
      tray_icon_.szInfoTitle,
      L"FENYVO \u0440\u0430\u0431\u043E\u0442\u0430\u0435\u0442 "
      L"\u0432 \u0444\u043E\u043D\u0435");
  wcscpy_s(tray_icon_.szInfo,
           L"\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F "
           L"\u0438 \u0437\u0432\u043E\u043D\u043A\u0438 "
           L"\u0431\u0443\u0434\u0443\u0442 \u043F\u0440\u0438\u0445\u043E\u0434\u0438\u0442\u044C. "
           L"\u0414\u043B\u044F \u043F\u043E\u043B\u043D\u043E\u0433\u043E "
           L"\u0432\u044B\u0445\u043E\u0434\u0430 \u043E\u0442\u043A\u0440\u043E\u0439\u0442\u0435 "
           L"\u043C\u0435\u043D\u044E \u0437\u043D\u0430\u0447\u043A\u0430.");
  Shell_NotifyIconW(NIM_MODIFY, &tray_icon_);
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
}
