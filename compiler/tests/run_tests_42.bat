@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%\..\.." >nul
set "ROOT=%CD%"
popd >nul

if defined NURL_ZIG (
    set "ZIG=%NURL_ZIG%"
) else (
    set "ZIG=zig"
)

pushd "%ROOT%" >nul
"%ZIG%" build test-42 -- %*
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
