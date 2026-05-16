@echo off
setlocal
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%scripts\Build-EmailPrintHostPackage.ps1"
set EXIT_CODE=%ERRORLEVEL%
echo.
if not "%EXIT_CODE%"=="0" (
  echo Package build failed with exit code %EXIT_CODE%.
) else (
  echo Package build completed successfully.
)
pause
exit /b %EXIT_CODE%
