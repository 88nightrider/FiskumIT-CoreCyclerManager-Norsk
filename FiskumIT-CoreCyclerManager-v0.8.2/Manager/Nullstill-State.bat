@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "STATE_FILE=%SCRIPT_DIR%state.json"

echo Nullstiller state.json...
echo.

if exist "%STATE_FILE%" (
    copy "%STATE_FILE%" "%STATE_FILE%.backup_%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%" >nul
    del "%STATE_FILE%"
)

echo Ferdig.
echo Start manageren paa nytt.
echo.
pause