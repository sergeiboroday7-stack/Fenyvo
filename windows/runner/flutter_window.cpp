#include "flutter_window.h"
#include "hex_video_audio_levels_windows.h"

#include <atomic>
#include <cwctype>
#include <filesystem>
#include <mutex>
#include <thread>
#include <utility>
#include <vector>

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

using HexAudioResult =
    flutter::MethodResult<flutter::EncodableValue>;

struct HexAudioReply {
  std::unique_ptr<HexAudioResult> result;
  std::vector<double> levels;
};

struct HexAudioReplyState {
  std::mutex mutex;
  std::vector<HexAudioReply> pending;
  std::atomic<bool> alive{true};
  std::atomic<int> in_flight{0};
};

namespace {
constexpr UINT kHexAudioReadyMessage = WM_APP + 93;
constexpr int kHexMaxConcurrent = 2;

std::wstring HexEnvironmentPath(const wchar_t* name) {
  const DWORD count = GetEnvironmentVariableW(name, nullptr, 0);
  if (count == 0 || count > 32768) return {};
  std::wstring value(count, L'\0');
  const DWORD written =
      GetEnvironmentVariableW(name, value.data(), count);
  if (written == 0 || written >= count) return {};
  value.resize(written);
  return value;
}

std::wstring HexCanonicalPath(const std::wstring& input) {
  try {
    if (input.empty()) return {};
    const auto candidate = std::filesystem::path(input);
    if (!candidate.is_absolute()) return {};
    auto result = std::filesystem::weakly_canonical(candidate).wstring();
    for (auto& character : result) character = std::towlower(character);
    return result;
  } catch (...) {
    return {};
  }
}

bool HexIsWithin(const std::wstring& path,
                 const std::wstring& root) {
  if (path.empty() || root.empty()) return false;
  if (path.size() <= root.size()) return false;
  if (path.compare(0, root.size(), root) != 0) return false;
  return path[root.size()] == L'\\' || path[root.size()] == L'/';
}

bool HexAllowedVideoPath(const std::wstring& input) {
  if (input.empty() || input.size() > 32767) return false;
  const std::wstring path = HexCanonicalPath(input);
  if (path.empty()) return false;

  const auto extension = std::filesystem::path(path).extension().wstring();
  if (extension != L".mp4" && extension != L".mov" &&
      extension != L".mkv" && extension != L".webm" &&
      extension != L".avi") {
    return false;
  }

  // Downloaded, locally decrypted media is in the app's cache.
  // Only cache directories inside Windows application-data roots
  // are allowed, not arbitrary paths supplied by the caller.
  for (const wchar_t* variable : {L"APPDATA", L"LOCALAPPDATA"}) {
    const auto root = HexCanonicalPath(HexEnvironmentPath(variable));
    if (!HexIsWithin(path, root)) continue;

    const std::wstring marker = L"\\spartan_media_cache\\";
    if (path.find(marker, root.size()) != std::wstring::npos) {
      return true;
    }
  }

  // Embedded media uses a generated name immediately inside
  // the application's system temporary directory.
  wchar_t temporary[32768] = {};
  const DWORD size = GetTempPathW(32768, temporary);
  if (size == 0 || size >= 32768) return false;

  const auto tempRoot = HexCanonicalPath(temporary);
  if (!HexIsWithin(path, tempRoot)) return false;

  const auto parent =
      HexCanonicalPath(std::filesystem::path(path).parent_path().wstring());
  if (parent != tempRoot) return false;

  const auto name = std::filesystem::path(path).filename().wstring();
  return name.rfind(L"spartan_private_video_", 0) == 0;
}

std::wstring HexUtf8ToWide(const std::string& input) {
  if (input.empty() || input.size() > 32767) return {};
  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring output(size, L'\0');
  const int written = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, input.data(),
      static_cast<int>(input.size()), output.data(), size);
  if (written != size) return {};
  return output;
}
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
  // Audio analysis is performed off the Flutter/UI thread.
  // Replies are delivered back on the Windows runner thread.
  hex_audio_reply_state_ = std::make_shared<HexAudioReplyState>();
  hex_audio_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "fenyvo/hex_video_audio",
          &flutter::StandardMethodCodec::GetInstance());

  hex_audio_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "analyze") {
          result->NotImplemented();
          return;
        }

        const auto* arguments = call.arguments();
        const auto* map = arguments
            ? std::get_if<flutter::EncodableMap>(arguments)
            : nullptr;
        if (!map) {
          result->Error("INVALID_ARGUMENTS", "Expected path map");
          return;
        }

        const auto item = map->find(flutter::EncodableValue("path"));
        if (item == map->end()) {
          result->Error("INVALID_PATH", "Missing local path");
          return;
        }

        const auto* utf8 = std::get_if<std::string>(&item->second);
        if (!utf8) {
          result->Error("INVALID_PATH", "Path must be text");
          return;
        }

        const std::wstring path = HexUtf8ToWide(*utf8);
        if (!HexAllowedVideoPath(path)) {
          result->Error("PATH_NOT_ALLOWED", "Video path not allowed");
          return;
        }

        const auto state = hex_audio_reply_state_;
        if (!state || !state->alive.load()) {
          result->Error("CHANNEL_CLOSED", "Audio channel unavailable");
          return;
        }

        if (state->in_flight.fetch_add(1) >= kHexMaxConcurrent) {
          state->in_flight.fetch_sub(1);
          result->Error("BUSY", "Audio analyzer busy");
          return;
        }

        const HWND window = GetHandle();

        try {
          std::thread(
              [state, window, path,
               result = std::move(result)]() mutable {
                const HRESULT com =
                    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

                std::vector<double> levels;
                if (SUCCEEDED(com)) {
                  try {
                    levels = AnalyzeHexVideoAudioWindows(path);
                  } catch (...) {
                    levels.clear();
                  }
                  CoUninitialize();
                }

                if (state->alive.load()) {
                  std::lock_guard<std::mutex> guard(state->mutex);
                  if (state->alive.load()) {
                    state->pending.push_back(
                        HexAudioReply{std::move(result),
                                      std::move(levels)});
                    PostMessageW(window, kHexAudioReadyMessage, 0, 0);
                  }
                }

                state->in_flight.fetch_sub(1);
              }).detach();
        } catch (...) {
          state->in_flight.fetch_sub(1);
          result->Error("WORKER_FAILED", "Cannot start analyzer");
        }
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
  if (hex_audio_reply_state_) {
    hex_audio_reply_state_->alive.store(false);
    std::lock_guard<std::mutex> guard(hex_audio_reply_state_->mutex);
    hex_audio_reply_state_->pending.clear();
  }
  hex_audio_channel_ = nullptr;
  hex_audio_reply_state_.reset();
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

  if (message == kHexAudioReadyMessage) {
    const auto state = hex_audio_reply_state_;
    if (state && state->alive.load()) {
      std::vector<HexAudioReply> replies;
      {
        std::lock_guard<std::mutex> guard(state->mutex);
        replies.swap(state->pending);
      }

      for (auto& reply : replies) {
        if (!reply.result) continue;
        flutter::EncodableList values;
        for (double level : reply.levels) {
          values.emplace_back(level);
        }
        reply.result->Success(flutter::EncodableValue(values));
      }
    }
    return 0;
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
