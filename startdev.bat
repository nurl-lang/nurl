@echo off
setlocal
pushd "%~dp0" >nul

if defined NURL_ZIG (
    set "ZIG=%NURL_ZIG%"
) else (
    set "ZIG=zig"
)

set "HELPER=%CD%\build\nurl-build.exe"
if not exist "%HELPER%" (
    "%ZIG%" build nurl-build
    set "RC=%ERRORLEVEL%"
    if not "%RC%"=="0" (
        popd >nul
        exit /b %RC%
    )
)

"%HELPER%" startdev %*
set "RC=%ERRORLEVEL%"

popd >nul
exit /b %RC%
