@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM ============================================================
REM  tools\nurlfmt\build.bat - build the nurlfmt formatter binary
REM                            on Windows.
REM
REM  Stage:
REM    1. Compile tools/nurlfmt/nurlfmt.nu to LLVM IR using
REM       build\nurlc.exe
REM    2. Link with stdlib\runtime.o -> build\nurlfmt.exe
REM
REM  Requires that build.bat has already run (so build\nurlc.exe
REM  and stdlib\runtime.o exist).
REM
REM  Windows counterpart of tools\nurlfmt\build.sh - same stages,
REM  same artefact name (.exe suffix).
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%\..\.." >nul
set "ROOT_DIR=%CD%"
popd >nul

set "NURLC=%ROOT_DIR%\build\nurlc.exe"
set "RUNTIME=%ROOT_DIR%\stdlib\runtime.o"
set "SRC=%ROOT_DIR%\tools\nurlfmt\nurlfmt.nu"

if not exist "%NURLC%" (
    echo ERROR: %NURLC% not found. 1>&2
    echo        Run build.bat first to bootstrap the compiler. 1>&2
    exit /b 1
)
if not exist "%RUNTIME%" (
    echo ERROR: %RUNTIME% not found. 1>&2
    echo        Run build.bat first to compile the runtime. 1>&2
    exit /b 1
)

REM ── Locate clang ─────────────────────────────────────────────
if not defined CLANG set "CLANG=clang"
where "%CLANG%" >nul 2>&1
if errorlevel 1 (
    set "CLANG="
    if exist "C:\Program Files\LLVM\bin\clang.exe" set "CLANG=C:\Program Files\LLVM\bin\clang.exe"
    if not defined CLANG if exist "C:\Program Files (x86)\LLVM\bin\clang.exe" set "CLANG=C:\Program Files (x86)\LLVM\bin\clang.exe"
    if not defined CLANG (
        echo ERROR: clang not found 1>&2
        exit /b 1
    )
)

if not exist "%ROOT_DIR%\build" mkdir "%ROOT_DIR%\build"

echo [1/2] %SRC% -^> build\nurlfmt.ll
"%NURLC%" "%SRC%" > "%ROOT_DIR%\build\nurlfmt.ll"
if errorlevel 1 (
    echo ERROR: NURL compilation failed 1>&2
    exit /b 1
)

REM runtime.o on Windows is built without optional sentinels (build.bat
REM links only WinHTTP). Match build.bat's link line: no -flto, no
REM -lm/-lpthread (winsock + WinHTTP are folded into runtime.c).
echo [2/2] build\nurlfmt.ll -^> build\nurlfmt.exe
"%CLANG%" -O2 "%ROOT_DIR%\build\nurlfmt.ll" "%RUNTIME%" -lwinhttp -o "%ROOT_DIR%\build\nurlfmt.exe"
if errorlevel 1 (
    echo ERROR: clang linking failed 1>&2
    exit /b 1
)

echo.
echo Done: %ROOT_DIR%\build\nurlfmt.exe
endlocal
