@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Always run the updater relative to THIS batch file, not the terminal folder.
set "MTG_ROOT=%~dp0"
set "MTG_UPDATER=%MTG_ROOT%tools\update-and-deploy.ps1"
set "MTG_UPDATE_STATUS=1"

echo.
echo ====================================================
echo   MTG TABLE - UPDATE FROM GITHUB AND DEPLOY
echo ====================================================
echo Folder: "%MTG_ROOT%"
echo.

if not exist "%MTG_UPDATER%" (
    echo [ERROR] Could not find tools\update-and-deploy.ps1
    echo [ERROR] Run UPDATE_TABLE.bat from the table repository root.
    goto :finish
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Windows PowerShell was not found.
    goto :finish
)

pushd "%MTG_ROOT%" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Could not open the table repository folder.
    goto :finish
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%MTG_UPDATER%"
set "MTG_UPDATE_STATUS=%ERRORLEVEL%"
popd

:finish
echo.
if "%MTG_UPDATE_STATUS%"=="0" (
    echo [SUCCESS] Update and deployment completed.
    echo NEXT: In Tabletop Simulator, run Smart Import / Save ^& Play.
) else (
    echo [FAILED] Updater exited with error code %MTG_UPDATE_STATUS%.
    echo Review the messages above. No TTS Save ^& Play until fixed.
)
echo.
rem Keep a double-clicked window readable, but never block VS Code tasks.
if /I "%~1"=="--no-pause" goto :end
if defined VSCODE_PID goto :end
echo Press any key to close...
pause >nul
:end
exit /b %MTG_UPDATE_STATUS%
