@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Fenyvo.ps1"
if errorlevel 1 (
  echo.
  echo Fenyvo installation failed.
  pause
  exit /b 1
)
endlocal
