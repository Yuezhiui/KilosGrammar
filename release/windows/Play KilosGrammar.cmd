@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Game.ps1"
if errorlevel 1 (
  echo.
  echo KilosGrammar could not start. Check the message above.
  pause
)
endlocal
