@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Setup-EmailPrintHost.ps1"
set EXIT_CODE=%ERRORLEVEL%
echo.
if not "%EXIT_CODE%"=="0" (
  echo Setup failed with exit code %EXIT_CODE%.
) else (
  echo Setup completed successfully.
)
pause
exit /b %EXIT_CODE%
