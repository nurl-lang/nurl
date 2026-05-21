@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM Compatibility wrapper. The canonical entrypoint is now `zig build nurlpkg`.
setlocal

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%\..\.." >nul

where zig >nul 2>&1
if errorlevel 1 (
    echo ERROR: zig not found on PATH 1>&2
    popd >nul
    exit /b 1
)

zig build nurlpkg
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
