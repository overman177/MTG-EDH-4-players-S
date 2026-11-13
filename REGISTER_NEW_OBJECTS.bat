@echo off
setlocal
cd /d "%~dp0"
echo === REGISTER NEW TTS OBJECTS ===
echo Export scripts using Smart Import / Get Lua Scripts first.
echo This command organizes and publishes incoming GUID files.
echo.
python tools\register_new_objects.py --apply --publish
set "REGISTER_STATUS=%ERRORLEVEL%"
echo.
if not "%REGISTER_STATUS%"=="0" (
    echo Registration stopped. See errors above. No scripts were uploaded if preflight failed.
) else (
    echo Registration finished. You can now request changes to these GUIDs from GitHub.
)
echo.
pause
exit /b %REGISTER_STATUS%
