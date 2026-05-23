@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM ============================================================
REM  build.bat - bootstrap the NURL compiler and run the test
REM              suite.  On full success, prints a single line:
REM
REM                  BUILD SUCCESS & TESTS PASSED
REM
REM  On any failure, the full build log or test-runner diff is
REM  printed so the cause is visible.
REM
REM  Windows counterpart of build.sh - same logic, same output.
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%" >nul

set "LOG=%TEMP%\nurl_build_%RANDOM%%RANDOM%.log"
type nul > "%LOG%"

REM ── Locate clang ─────────────────────────────────────────────
set "CLANG=clang"
where clang >nul 2>&1
if errorlevel 1 (
    set "CLANG="
    if exist "C:\Program Files\LLVM\bin\clang.exe" set "CLANG=C:\Program Files\LLVM\bin\clang.exe"
    if not defined CLANG if exist "C:\Program Files (x86)\LLVM\bin\clang.exe" set "CLANG=C:\Program Files (x86)\LLVM\bin\clang.exe"
    if not defined CLANG (
        echo ERROR: clang not found
        call :cleanup
        popd >nul
        exit /b 1
    )
)

if not exist build mkdir build

REM ── runtime ──────────────────────────────────────────────────
set "LABEL=runtime"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" -c stdlib/runtime.c -o stdlib/runtime.o
"%CLANG%" -c stdlib/runtime.c -o stdlib/runtime.o >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

REM ── canvas ──────────────────────────────────────────────────
REM canvas.o is ALWAYS built. When SDL2 dev headers are available we
REM compile the real SDL2 back-end (-DNURL_HAVE_SDL2); otherwise a
REM stub back-end is compiled that prints a diagnostic and exits if
REM the program actually calls into the canvas API. This way:
REM   - Non-canvas programs link cleanly on every system, no SDL2.
REM   - Canvas programs on stub builds fail loudly with clear guidance.
REM   - Canvas programs on SDL2 builds get the full native window.
set "SDL2_INC="
if exist "C:\SDL2\include\SDL2\SDL.h" set "SDL2_INC=C:\SDL2\include"
if not defined SDL2_INC if exist "C:\SDL2\include\SDL.h" set "SDL2_INC=C:\SDL2"
if not defined SDL2_INC if exist "%VCPKG_ROOT%\installed\x64-windows\include\SDL2\SDL.h" set "SDL2_INC=%VCPKG_ROOT%\installed\x64-windows\include"
if not defined SDL2_INC if exist "C:\vcpkg\installed\x64-windows\include\SDL2\SDL.h" set "SDL2_INC=C:\vcpkg\installed\x64-windows\include"
set "LABEL=canvas"
>>"%LOG%" echo.
if defined SDL2_INC (
    >>"%LOG%" echo [%LABEL%] "%CLANG%" -c stdlib/canvas.c -DNURL_HAVE_SDL2 -I"%SDL2_INC%" -o stdlib/canvas.o
    "%CLANG%" -c stdlib/canvas.c -DNURL_HAVE_SDL2 -I"%SDL2_INC%" -o stdlib/canvas.o >>"%LOG%" 2>&1
) else (
    >>"%LOG%" echo [%LABEL%] "%CLANG%" -c stdlib/canvas.c -o stdlib/canvas.o  ^(stub: no SDL2 headers found^)
    "%CLANG%" -c stdlib/canvas.c -o stdlib/canvas.o >>"%LOG%" 2>&1
)
if errorlevel 1 goto :failed

REM Marker so nurl.bat knows whether to link -lSDL2 and ship SDL2.dll
REM for canvas-using programs. Present = real SDL2 back-end in canvas.o.
if defined SDL2_INC (
    > stdlib\canvas.sdl2 echo 1
) else (
    if exist stdlib\canvas.sdl2 del /q stdlib\canvas.sdl2
)

REM ── clean ────────────────────────────────────────────────────
set "LABEL=clean"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%]
del /q build\nurlc_lastgood.bin.exe build\nurlc_self.ll build\nurlc_self.exe build\nurlc_self2.ll build\nurlc_self2.exe build\nurlc.exe >>"%LOG%" 2>&1

REM ── stage0 link ──────────────────────────────────────────────
REM Python-free bootstrap: link the committed `nurlc_lastgood.ll`
REM snapshot (regenerate via Linux/macOS `./build.sh --refresh-bootstrap`
REM when a grammar / runtime-ABI change leaves it unable to compile
REM current nurlc.nu). The .ll carries no `target triple` directive
REM so clang on Windows picks the host triple automatically.
set "LABEL=stage0 link"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" -O2 compiler/nurlc_lastgood.ll stdlib/runtime.o -lwinhttp -o build/nurlc_lastgood.bin.exe
"%CLANG%" -O2 compiler/nurlc_lastgood.ll stdlib/runtime.o -lwinhttp -o build/nurlc_lastgood.bin.exe >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

REM ── stage1 ir ────────────────────────────────────────────────
set "LABEL=stage1 ir"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] build\nurlc_lastgood.bin.exe compiler\nurlc.nu ^> build\nurlc_self.ll
build\nurlc_lastgood.bin.exe compiler\nurlc.nu > build\nurlc_self.ll 2>>"%LOG%"
if errorlevel 1 goto :failed

REM ── stage1 link ──────────────────────────────────────────────
set "LABEL=stage1 link"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" -O2 build/nurlc_self.ll stdlib/runtime.o -lwinhttp -o build/nurlc_self.exe
"%CLANG%" -O2 build/nurlc_self.ll stdlib/runtime.o -lwinhttp -o build/nurlc_self.exe >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

REM ── stage2 ir ────────────────────────────────────────────────
set "LABEL=stage2 ir"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] build\nurlc_self.exe compiler\nurlc.nu ^> build\nurlc_self2.ll
build\nurlc_self.exe compiler\nurlc.nu > build\nurlc_self2.ll 2>>"%LOG%"
if errorlevel 1 goto :failed

REM ── stage2 link ──────────────────────────────────────────────
set "LABEL=stage2 link"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" -O2 build/nurlc_self2.ll stdlib/runtime.o -lwinhttp -o build/nurlc_self2.exe
"%CLANG%" -O2 build/nurlc_self2.ll stdlib/runtime.o -lwinhttp -o build/nurlc_self2.exe >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

REM ── Fixed-point check ────────────────────────────────────────
fc /B build\nurlc_self.ll build\nurlc_self2.ll >nul 2>&1
if errorlevel 1 (
    >>"%LOG%" echo Fixed point NOT reached - nurlc_self and nurlc_self2 differ.
    >>"%LOG%" echo Run: fc build\nurlc_self.ll build\nurlc_self2.ll
    set "LABEL=bootstrap fixed point"
    goto :failed
)

copy /Y build\nurlc_self2.exe build\nurlc.exe >nul
copy /Y build\nurlc.exe nurlc.exe >nul

REM ── Test suite ───────────────────────────────────────────────
set "TESTOUT=%TEMP%\nurl_testout_%RANDOM%%RANDOM%.log"
call "%SCRIPT_DIR%\compiler\tests\run_tests.bat" > "%TESTOUT%" 2>&1
if errorlevel 1 goto :tests_failed

echo BUILD SUCCESS ^& TESTS PASSED
REM nurlc_lastgood.{nu,ll} are NOT auto-updated; refresh via
REM `./build.sh --refresh-bootstrap` (Linux/macOS) and commit both.
del "%TESTOUT%" 2>nul
call :cleanup
popd >nul
exit /b 0

:tests_failed
echo BUILD DIDN'T FAIL but TESTS FAILED
echo ====================================================
type "%TESTOUT%"
del "%TESTOUT%" 2>nul
call :cleanup
popd >nul
exit /b 1

:failed
echo BUILD FAILED: %LABEL%
echo ====================================================
type "%LOG%"
call :cleanup
popd >nul
exit /b 1

:cleanup
if exist "%LOG%" del "%LOG%" 2>nul
exit /b 0
