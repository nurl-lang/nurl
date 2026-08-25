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
REM once declared. Compression is pure NURL now (deflate in §8 P6, zstd
REM in std\zstd.nu), so nothing here is load-bearing for compress.nu any
REM more; it stays for whatever else a user FFI-declares. For each lib found we drop the
REM stdlib\runtime.<name> sentinel nurlc's FFI-lib check consults and
REM accumulate its link fragment in stdlib\runtime.winlibs for nurl.bat /
REM tools\nurlpkg\build.bat to append. zlib additionally needs
REM -DNURL_HAVE_ZLIB + its include so runtime.c's gzip bridge (§22) builds.
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
REM Resolve the ACTUAL static-lib basename present in the lib dir. `-l<name>`
REM needs <name>.lib to exist or the linker dies with LNK1181 "cannot open
REM input file '<name>.lib'" (issue #229). vcpkg ships zlib's release static
REM lib under DIFFERENT names across versions: 1.3.1 produced zlib.lib, but
REM 1.3.2#1 adopted zlib's new CMake (-DZLIB_BUILD_STATIC) and renames the
REM Windows static lib to zs.lib (its zlib.pc is rewritten -lz -> -lzs) — the
REM exact mismatch that broke the Windows release. Never assume the name:
REM probe for the file and derive the -l name from it. Enable zlib ONLY when
REM zlib.h AND a matching .lib are both present.
set "ZLIB_LIBNAME="
if defined ZLIB_INC (
    for %%N in (zlib zlibstatic zs z libz) do (
        if not defined ZLIB_LIBNAME if exist "!ZLIB_LIBDIR!\%%N.lib" set "ZLIB_LIBNAME=%%N"
    )
    echo [diag] zlib: ZLIB_LIBDIR="!ZLIB_LIBDIR!" *.lib:
    dir /b "!ZLIB_LIBDIR!\*.lib" 2>nul
)
if defined ZLIB_LIBNAME (
    set ZLIB_CFLAGS=-DNURL_HAVE_ZLIB -I"!ZLIB_INC!"
    > stdlib\runtime.z echo 1
    set WINLIBS=!WINLIBS! -L"!ZLIB_LIBDIR!" -l!ZLIB_LIBNAME!
    echo [info] zlib enabled: -l!ZLIB_LIBNAME! from "!ZLIB_LIBDIR!"
) else (
    if exist stdlib\runtime.z del /q stdlib\runtime.z
    if defined ZLIB_INC echo [warn] zlib.h at "!ZLIB_INC!" but no zlib*.lib in "!ZLIB_LIBDIR!" - zlib disabled
)

REM zstd is pure NURL over stdlib\std\zstd.nu now - no library, no sentinel.
if exist stdlib\runtime.zstd del /q stdlib\runtime.zstd

REM ── CUDA driver + NVRTC sentinels (ALWAYS on — stub-backed) ──
REM Mirrors build.sh §"CUDA driver + NVRTC sentinels". packages\gpu binds
REM the CUDA Driver API (& `cuda` @ cu…) and NVRTC (& `nvrtc` @ nvrtc…)
REM directly, with no runtime.c bridge. These are the two FFI libs that
REM have FALLBACK STUB SOURCES (stdlib\{cuda,nvrtc}_stubs.c), which
REM nurl.bat compiles into the image when no CUDA Toolkit is installed —
REM so a gpu-importing program links and runs on a driverless box and
REM packages\gpu falls back to its CPU backend. Because the fallback always
REM exists, the COMPILE-TIME sentinel must not depend on any probe: gate it
REM on the host and every Windows user without a Toolkit gets 40-odd
REM "no build-time sentinel 'stdlib/runtime.cuda'" errors from nurlc for a
REM package (anomaly, tensor, gpukit) that never needed a GPU in the first
REM place. Stub-backed libs get an unconditional sentinel; nurl.bat decides
REM real-vs-stub at LINK time, where the answer actually matters.
> stdlib\runtime.cuda echo 1
> stdlib\runtime.nvrtc echo 1
if defined CUDA_PATH (
    echo [info] CUDA Toolkit at "%CUDA_PATH%" - nurl.bat links the real driver + NVRTC
) else (
    echo [info] no CUDA Toolkit - cu*/nvrtc* link against stubs; packages\gpu uses its CPU backend
)

REM ── version header (mirrors build.sh) ────────────────────────
REM Bake the toolchain version into runtime.o so `nurlc --version` /
REM `nurlpkg --version` report the real version instead of "unknown".
REM Single source of truth: tools\version.bat (git describe / CHANGELOG).
REM The header is git-ignored and rebuilt every run; it lives in runtime.o,
REM not nurlc.nu's IR, so the bootstrap fixed point never churns on a bump.
set "NURL_VER="
for /f "delims=" %%v in ('call "%SCRIPT_DIR%\tools\version.bat" 2^>nul') do set "NURL_VER=%%v"
if not defined NURL_VER set "NURL_VER=v0.0.0"
> stdlib\nurl_version_gen.h echo #define NURL_VERSION "!NURL_VER!"
echo [info] version: !NURL_VER!

REM ── runtime ──────────────────────────────────────────────────
set "LABEL=runtime"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" -c stdlib/runtime.c !ZLIB_CFLAGS! -o stdlib/runtime.o
"%CLANG%" -c stdlib/runtime.c !ZLIB_CFLAGS! -o stdlib/runtime.o >>"%LOG%" 2>&1
if errorlevel 1 goto :failed

REM ── A second runtime, for the MinGW ABI ──────────────────────
REM The object above is clang-built and therefore MSVC-ABI: it references
REM _setjmp, __chkstk and _fltused, none of which MinGW's CRT provides.
REM `zig cc` targets x86_64-windows-gnu, so a program linked by the
REM bundled zig against it dies on exactly those three symbols. The two
REM ABIs cannot share one object, so build a second one with zig when a
REM zig is around; nurl.bat picks whichever matches the compiler it uses,
REM and install-toolchain ships the whole stdlib tree, so it travels.
REM
REM No !ZLIB_CFLAGS! here: it is an MSVC vcpkg include path, and there is
REM nothing left in the runtime for it to feed — gzip/deflate became pure
REM NURL in §8 P6, so -DNURL_HAVE_ZLIB no longer selects anything. The
REM object references no compression library at all, which is what lets nurl.bat
REM drop stdlib\winlib from a MinGW link without leaving a dangling
REM symbol behind.
set "ZIG_MINGW="
if defined NURL_BUNDLE_ZIG if exist "%NURL_BUNDLE_ZIG%\zig.exe" set "ZIG_MINGW=%NURL_BUNDLE_ZIG%\zig.exe"
if not defined ZIG_MINGW if defined NURL_ZIG if exist "%NURL_ZIG%" set "ZIG_MINGW=%NURL_ZIG%"
if not defined ZIG_MINGW if exist "%SCRIPT_DIR%\vendor\zig\zig.exe" set "ZIG_MINGW=%SCRIPT_DIR%\vendor\zig\zig.exe"
if defined ZIG_MINGW (
    >>"%LOG%" echo [%LABEL%] "!ZIG_MINGW!" cc -target x86_64-windows-gnu -O2 -c stdlib/runtime.c -o stdlib\runtime.mingw.o
    "!ZIG_MINGW!" cc -target x86_64-windows-gnu -O2 -c stdlib/runtime.c -o stdlib\runtime.mingw.o >>"%LOG%" 2>&1
    if errorlevel 1 goto :failed
    echo [info] MinGW runtime: stdlib\runtime.mingw.o ^(via "!ZIG_MINGW!"^)
) else (
    if exist stdlib\runtime.mingw.o del /q stdlib\runtime.mingw.o
    >>"%LOG%" echo [info] no zig found - stdlib\runtime.mingw.o not built
    echo [info] no zig found - programs will need clang to link
)

REM Persist the accumulated link fragment for the FFI consumers.
if defined WINLIBS (
    > stdlib\runtime.winlibs echo !WINLIBS!
    >>"%LOG%" echo [info] FFI libs detected -!WINLIBS!
    echo [info] runtime.winlibs =!WINLIBS!
) else (
    if exist stdlib\runtime.winlibs del /q stdlib\runtime.winlibs
    >>"%LOG%" echo [info] no vcpkg FFI libs detected
)

REM ── Bundle the FFI libs for a SELF-CONTAINED, relocatable toolchain ───
REM runtime.winlibs above points at the vcpkg lib dir on THIS machine — fine
REM for building nurlpkg.exe here, but the shipped runtime.o is compiled with
REM -DNURL_HAVE_ZLIB so it references deflate/inflate, meaning EVERY user link
REM needs zlib. If only the build-machine vcpkg path is recorded, every link
REM on a user box without vcpkg dies with "could not open 'zs.lib'". So copy
REM the actual .lib files into stdlib\winlib\ and record a relocatable link
REM fragment ($NURL_LIB$ placeholder) that nurl.bat resolves against the
REM install prefix at link time. install-toolchain ships stdlib\winlib\
REM verbatim; the build-time runtime.winlibs stays for build-time consumers
REM (nurlpkg\build.bat, run_tests.ps1).
if defined WINLIBS (
    if not exist stdlib\winlib mkdir stdlib\winlib
    set "RELOC="
    if defined ZLIB_LIBNAME if exist "!ZLIB_LIBDIR!\!ZLIB_LIBNAME!.lib" (
        copy /y "!ZLIB_LIBDIR!\!ZLIB_LIBNAME!.lib" "stdlib\winlib\!ZLIB_LIBNAME!.lib" >nul
        set "RELOC=!RELOC! -l!ZLIB_LIBNAME!"
    )

    > stdlib\winlib\winlibs.reloc echo  -L"$NURL_LIB$"!RELOC!
    echo [info] bundled FFI libs -^> stdlib\winlib  reloc:!RELOC!
) else (
    if exist stdlib\winlib rmdir /s /q stdlib\winlib
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

REM ── Optimisation level for the throwaway stages ──────────────
REM Stages 0 and 1 are scaffolding: neither binary is shipped or
REM benchmarked, and each compiles nurlc.nu exactly once before being
REM deleted. Optimising them spends far more link time than the faster
REM compile gives back, so they are built -O0 and only stage 2 — the
REM one copied to build\nurlc.exe — is built -O2. The IR each stage
REM emits is byte-identical either way, and the fixed-point check below
REM still proves it. See build.sh for the measured Linux numbers.
set "BOOT_OPT=-O0"

REM ── stage0 link ──────────────────────────────────────────────
REM Python-free bootstrap: link the committed `nurlc_lastgood.ll`
REM snapshot (regenerate via Linux/macOS `./build.sh --refresh-bootstrap`
REM when a grammar / runtime-ABI change leaves it unable to compile
REM current nurlc.nu). The .ll carries no `target triple` directive
REM so clang on Windows picks the host triple automatically.
set "LABEL=stage0 link"
>>"%LOG%" echo.
>>"%LOG%" echo [%LABEL%] "%CLANG%" %BOOT_OPT% compiler/nurlc_lastgood.ll stdlib/runtime.o -lwinhttp -o build/nurlc_lastgood.bin.exe
"%CLANG%" %BOOT_OPT% compiler/nurlc_lastgood.ll stdlib/runtime.o -lwinhttp -o build/nurlc_lastgood.bin.exe >>"%LOG%" 2>&1
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
>>"%LOG%" echo [%LABEL%] "%CLANG%" %BOOT_OPT% build/nurlc_self.ll stdlib/runtime.o -lwinhttp -o build/nurlc_self.exe
"%CLANG%" %BOOT_OPT% build/nurlc_self.ll stdlib/runtime.o -lwinhttp -o build/nurlc_self.exe >>"%LOG%" 2>&1
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
REM Requires PowerShell 7+ (pwsh) for ForEach-Object -Parallel. There is
REM no Windows-PowerShell 5.1 fallback: the run_tests.bat that used to
REM serve as one compared against a monolithic correct.txt that is not
REM in the repo, so its first run wrote its own baseline and declared
REM success — a runner that cannot fail — and it carried a third, stale
REM copy of the by-name skip lists that test_skips.sh replaced. Deleted
REM rather than repaired: a missing pwsh already exits non-zero below,
REM which is the honest answer.
set "PWSH=pwsh"
where pwsh >nul 2>&1
if errorlevel 1 (
    REM Skipping tests is a DEGRADED result, not success: exit non-zero so
    REM CI (and scripts) can't mistake an untested build for a tested one.
    REM Set NURL_ALLOW_NOTESTS=1 to accept the skip locally.
    if "%NURL_ALLOW_NOTESTS%"=="1" (
        echo BUILD SUCCESS, TESTS SKIPPED - PowerShell 7+ ^(pwsh^) not found ^(NURL_ALLOW_NOTESTS=1^).
        del "%TESTOUT%" 2>nul
        call :cleanup
        popd >nul
        exit /b 0
    )
    echo BUILD SUCCESS, but TESTS DID NOT RUN: PowerShell 7+ ^(pwsh^) not found.
    echo Install pwsh ^(winget install Microsoft.PowerShell^) and re-run,
    echo or set NURL_ALLOW_NOTESTS=1 to accept an untested build.
    del "%TESTOUT%" 2>nul
    call :cleanup
    popd >nul
    exit /b 2
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
