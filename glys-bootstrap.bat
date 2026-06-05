@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install.ps1" %*
set EXIT_CODE=%ERRORLEVEL%
echo.
if %EXIT_CODE% EQU 0 (
    echo Bootstrap completed successfully.
) else (
    echo Bootstrap finished with exit code %EXIT_CODE%. See output above.
)
echo Press any key to close...
pause > nul
exit /b %EXIT_CODE%
