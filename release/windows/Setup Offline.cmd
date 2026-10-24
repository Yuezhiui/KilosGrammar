@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-OnSchoolPC.ps1"
if errorlevel 1 (
  echo.
  echo Offline setup did not complete. Read the message above.
)
pause
endlocal
