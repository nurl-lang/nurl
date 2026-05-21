@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM Compatibility wrapper. The canonical Windows entrypoint is now `zig build`.
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

set "NO_TESTS=0"
set "SAN=0"

:parse_args
if "%~1"=="" goto :run
if /i "%~1"=="--no-tests" (
    set "NO_TESTS=1"
    shift
    goto :parse_args
)
if /i "%~1"=="--san" (
    set "SAN=1"
    shift
    goto :parse_args
)
if /i "%~1"=="-h" (
    zig build --help
    set "RC=%ERRORLEVEL%"
    popd >nul
    exit /b %RC%
)
if /i "%~1"=="--help" (
    zig build --help
    set "RC=%ERRORLEVEL%"
    popd >nul
    exit /b %RC%
)
echo unknown arg: %~1 1>&2
popd >nul
exit /b 2

:run
if "%SAN%"=="1" (
    if "%NO_TESTS%"=="1" (
        zig build bootstrap -Dsan=true
    ) else (
        zig build -Dsan=true
    )
) else (
    if "%NO_TESTS%"=="1" (
        zig build bootstrap
    ) else (
        zig build check
    )
)
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
