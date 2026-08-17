@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM ============================================================
REM  tools\nurlpkg\build.bat - build the nurlpkg package manager
REM                            binary on Windows.
REM
REM  Stage:
REM    1. Compile tools/nurlpkg/main.nu to LLVM IR using
REM       build\nurlc.exe
REM    2. Link with stdlib\runtime.o -> build\nurlpkg.exe
REM
REM  Requires that build.bat has already run.
REM
REM  Windows counterpart of tools\nurlpkg\build.sh.
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%\..\.." >nul
set "ROOT_DIR=%CD%"
popd >nul

set "NURLC=%ROOT_DIR%\build\nurlc.exe"
set "RUNTIME=%ROOT_DIR%\stdlib\runtime.o"
set "SRC=%ROOT_DIR%\tools\nurlpkg\main.nu"

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

echo [1/2] %SRC% -^> build\nurlpkg.ll
"%NURLC%" "%SRC%" > "%ROOT_DIR%\build\nurlpkg.ll"
if errorlevel 1 (
    echo ERROR: NURL compilation failed 1>&2
    exit /b 1
)

REM nurlpkg imports stdlib\ext\compress.nu, whose codecs are pure NURL;
REM the recorded fragment is kept for any other FFI. build.bat records the
REM resolved link fragment in stdlib\runtime.winlibs when they were
REM detected (issue #229).
set "WINLIBS="
if exist "%ROOT_DIR%\stdlib\runtime.winlibs" set /p WINLIBS=<"%ROOT_DIR%\stdlib\runtime.winlibs"
echo [diag] linking with WINLIBS=!WINLIBS!

echo [2/2] build\nurlpkg.ll -^> build\nurlpkg.exe
"%CLANG%" -O2 "%ROOT_DIR%\build\nurlpkg.ll" "%RUNTIME%" -lwinhttp !WINLIBS! -o "%ROOT_DIR%\build\nurlpkg.exe"
if errorlevel 1 (
    echo ERROR: clang linking failed 1>&2
    exit /b 1
)

echo.
echo Done: %ROOT_DIR%\build\nurlpkg.exe
endlocal
