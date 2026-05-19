@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM ============================================================
REM  nurlfmt.bat - thin launcher for the NURL canonical formatter
REM                on Windows.
REM
REM  Usage:  nurlfmt.bat [OPTIONS] [FILE...]
REM
REM  Forwards all arguments to build\nurlfmt.exe. Builds the binary
REM  on first run via tools\nurlfmt\build.bat if it is missing.
REM
REM  See docs/FORMAT.md for the formatting specification and the
REM  full CLI surface.
REM
REM  Windows counterpart of nurlfmt.sh.
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "NURLFMT=%SCRIPT_DIR%\build\nurlfmt.exe"

if not exist "%NURLFMT%" (
    echo [nurlfmt.bat] build\nurlfmt.exe missing - bootstrapping... 1>&2
    call "%SCRIPT_DIR%\tools\nurlfmt\build.bat"
    if errorlevel 1 (
        echo [nurlfmt.bat] bootstrap failed 1>&2
        exit /b 1
    )
)

"%NURLFMT%" %*
exit /b !errorlevel!
