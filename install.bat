@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%" >nul

where zig >nul 2>&1
if errorlevel 1 (
    echo ERROR: zig not found on PATH 1>&2
    popd >nul
    exit /b 1
)

zig build install-dev -- %*
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
