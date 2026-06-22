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

REM --no-tests: bootstrap only (fixed point), skip the test suite. Used by
REM the release workflow, which packages the toolchain rather than gating
REM tests (CI does that separately). Mirrors build.sh --no-tests.
set "NO_TESTS=0"
if /i "%~1"=="--no-tests" set "NO_TESTS=1"

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

REM ── FFI library detection (vcpkg) — issue #229 ───────────────
REM Mirror build.sh's feature-lib wiring on Windows. Probe the vcpkg
REM install (static triplet preferred so produced exes carry no DLL
REM dependency, then x64-windows) for the libs stdlib\ext\compress.nu
REM declares — zlib (& `z`) and zstd (& `zstd`) — which nurlpkg pulls in
REM (gunzip + zstd for registry tarballs). For each lib found we drop the
REM stdlib\runtime.<name> sentinel nurlc's FFI-lib check consults and
REM accumulate its link fragment in stdlib\runtime.winlibs for nurl.bat /
REM tools\nurlpkg\build.bat to append. zlib additionally needs
REM -DNURL_HAVE_ZLIB + its include so runtime.c's gzip bridge (§22) builds;
REM zstd is pure-NURL FFI (no runtime.c bridge) so it needs sentinel+link
REM only. Without these, compress.nu's gzip_*/zstd_* and nurlpkg won't build.
set "ZLIB_CFLAGS="
set "WINLIBS="
set "VCPKG_INC="
set "VCPKG_LIBDIR="
for %%T in (x64-windows-static x64-windows) do (
    if not defined VCPKG_INC if exist "%VCPKG_ROOT%\installed\%%T\include" (
        set "VCPKG_INC=%VCPKG_ROOT%\installed\%%T\include"
        set "VCPKG_LIBDIR=%VCPKG_ROOT%\installed\%%T\lib"
    )
    if not defined VCPKG_INC if exist "C:\vcpkg\installed\%%T\include" (
        set "VCPKG_INC=C:\vcpkg\installed\%%T\include"
        set "VCPKG_LIBDIR=C:\vcpkg\installed\%%T\lib"
    )
)

REM zlib — vcpkg, or a bundled C:\zlib.
set "ZLIB_INC="
set "ZLIB_LIBDIR="
if defined VCPKG_INC if exist "!VCPKG_INC!\zlib.h" (
    set "ZLIB_INC=!VCPKG_INC!"
    set "ZLIB_LIBDIR=!VCPKG_LIBDIR!"
)
if not defined ZLIB_INC if exist "C:\zlib\include\zlib.h" (
    set "ZLIB_INC=C:\zlib\include"
    set "ZLIB_LIBDIR=C:\zlib\lib"
)
if defined ZLIB_INC (
    set "ZLIB_LIBNAME=zlib"
    if exist "!ZLIB_LIBDIR!\zlibstatic.lib" set "ZLIB_LIBNAME=zlibstatic"
    set ZLIB_CFLAGS=-DNURL_HAVE_ZLIB -I"!ZLIB_INC!"
    > stdlib\runtime.z echo 1
    set WINLIBS=!WINLIBS! -L"!ZLIB_LIBDIR!" -l!ZLIB_LIBNAME!
) else (
    if exist stdlib\runtime.z del /q stdlib\runtime.z
)

REM zstd — pure-NURL FFI: sentinel + link only.
set "HAVE_ZSTD="
if defined VCPKG_INC if exist "!VCPKG_INC!\zstd.h" set "HAVE_ZSTD=1"
if defined HAVE_ZSTD (
    > stdlib\runtime.zstd echo 1
    set WINLIBS=!WINLIBS! -L"!VCPKG_LIBDIR!" -lzstd
) else (
    if exist stdlib\runtime.zstd del /q stdlib\runtime.zstd
)

REM ── runtime ──────────────────────────────────────────────────
set "LABEL=runtime"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" -c stdlib/runtime.c !ZLIB_CFLAGS! -o stdlib/runtime.o
"%CLANG%" -c stdlib/runtime.c !ZLIB_CFLAGS! -o stdlib/runtime.o >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

REM Persist the accumulated link fragment for the FFI consumers.
if defined WINLIBS (
    > stdlib\runtime.winlibs echo !WINLIBS!
    >>"%LOG%" echo [info] FFI libs detected -!WINLIBS!
) else (
    if exist stdlib\runtime.winlibs del /q stdlib\runtime.winlibs
    >>"%LOG%" echo [info] no vcpkg zlib/zstd - compress.nu / nurlpkg unavailable
)

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

if "%NO_TESTS%"=="1" (
    echo BUILD SUCCESS ^(tests skipped via --no-tests^)
    call :cleanup
    popd >nul
    exit /b 0
)

REM ── Test suite ───────────────────────────────────────────────
REM Per-test golden runner, ported from run_tests.sh, with Windows
REM goldens in compiler\tests\outputs-windows\ and parallel execution.
REM Requires PowerShell 7+ (pwsh) for ForEach-Object -Parallel; the
REM legacy run_tests.bat (monolithic correct.txt) is kept only as a
REM Windows-PowerShell 5.1 fallback.
set "PWSH=pwsh"
where pwsh >nul 2>&1
if errorlevel 1 (
    echo BUILD SUCCESS, but PowerShell 7+ ^(pwsh^) not found - skipping tests.
    echo Install pwsh and run: pwsh compiler\tests\run_tests.ps1
    del "%TESTOUT%" 2>nul
    call :cleanup
    popd >nul
    exit /b 0
)
set "TESTOUT=%TEMP%\nurl_testout_%RANDOM%%RANDOM%.log"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\compiler\tests\run_tests.ps1" > "%TESTOUT%" 2>&1
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
