@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update-and-deploy.ps1"
set "MTG_UPDATE_STATUS=%ERRORLEVEL%"
echo.
if not "%MTG_UPDATE_STATUS%"=="0" (
    echo Update failed. Read the messages above before using Smart Import.
) else (
    echo Ready. In Tabletop Simulator, run Smart Import / Save ^& Play.
)
echo.
pause
exit /b %MTG_UPDATE_STATUS%
