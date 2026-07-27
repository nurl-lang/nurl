@echo off
setlocal enabledelayedexpansion

REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM ============================================================
REM  nurl.bat — compile a .nu file to a native executable
REM
REM  Usage:  nurl.bat [flags] <file.nu> [output_name]
REM
REM  Flags (all must come before the source file):
REM    --emit-ir            Stop after stage 1, leave only the .ll
REM    --emit-asm           Emit .s (native assembly) next to the .ll
REM    -O0 / -O1 / -O2 / -O3   Clang optimisation level (default -O2)
REM    -g / --debug         Pass -g to clang (DWARF/CodeView line tables)
REM
REM  Examples:
REM    nurl.bat hello.nu               → hello.exe
REM    nurl.bat src\myprog.nu prog     → prog.exe
REM    nurl.bat --emit-ir hello.nu     → hello.ll  (skip link)
REM    nurl.bat --emit-asm hello.nu    → hello.s   (skip link)
REM    nurl.bat -O0 -g hello.nu        → hello.exe with debug info, no opt
REM
REM  Note: cmd.exe splits on `=`, so `--emit-ir` is the canonical form.
REM  `--emit=ir` also works if quoted: nurl.bat "--emit=ir" file.nu
REM
REM  Requires nurlc.exe and stdlib\runtime.o in the same
REM  directory as this script (or nurlc.exe in PATH).
REM ============================================================

REM ── Parse leading flags ──────────────────────────────────────
set "EMIT_IR=0"
set "EMIT_ASM=0"
set "DEBUG_INFO=0"
set "CLI_OPT="

REM -- version / upgrade: whole-toolchain commands, no source file --
REM `nurl upgrade` is the canonical name for a toolchain upgrade (it is
REM what the "a newer NURL toolchain is available" notice prints). The
REM implementation lives in nurlpkg; every spelling a user might guess
REM lands there. `nurlpkg update` is NOT one of them - that moves a
REM project's dependency requirements.
if /i "%~1"=="--version"    goto show_version
if /i "%~1"=="-v"           goto show_version
if /i "%~1"=="version"      goto show_version
if /i "%~1"=="upgrade"      goto do_upgrade
if /i "%~1"=="update"       goto do_upgrade
if /i "%~1"=="self-update"  goto do_upgrade
if /i "%~1"=="self-upgrade" goto do_upgrade

:parse_flags
if /i "%~1"=="--emit-ir"  set "EMIT_IR=1"     & shift & goto parse_flags
if /i "%~1"=="--emit=ir"  set "EMIT_IR=1"     & shift & goto parse_flags
if /i "%~1"=="--emit-asm" set "EMIT_ASM=1"    & shift & goto parse_flags
if /i "%~1"=="--emit=asm" set "EMIT_ASM=1"    & shift & goto parse_flags
if /i "%~1"=="-g"         set "DEBUG_INFO=1"  & shift & goto parse_flags
if /i "%~1"=="--debug"    set "DEBUG_INFO=1"  & shift & goto parse_flags
if /i "%~1"=="-O0"        set "CLI_OPT=-O0"   & shift & goto parse_flags
if /i "%~1"=="-O1"        set "CLI_OPT=-O1"   & shift & goto parse_flags
if /i "%~1"=="-O2"        set "CLI_OPT=-O2"   & shift & goto parse_flags
if /i "%~1"=="-O3"        set "CLI_OPT=-O3"   & shift & goto parse_flags

if "%~1"=="" (
    echo Usage: nurl.bat [flags] ^<file.nu^> [output_name]
    echo.
    echo  Flags: --emit-ir ^| --emit-asm ^| -O0..-O3 ^| -g ^| --debug
    echo.
    echo  Compiles a NURL source file to a native Windows executable.
    echo.
    echo  nurl --version ^| -v         Print the toolchain version.
    echo  nurl upgrade [--check]      Upgrade the toolchain in place.
    echo  The intermediate .ll file is kept alongside the output.
    exit /b 1
)

set "SRCFILE=%~1"
if not exist "%SRCFILE%" (
    echo ERROR: Source file not found: %SRCFILE%
    exit /b 1
)

REM ── Derive output names ──────────────────────────────────────
if "%~2"=="" (
    set "OUTBASE=%~n1"
) else (
    set "OUTBASE=%~2"
)
set "LLFILE=%OUTBASE%.ll"
set "SFILE=%OUTBASE%.s"
set "EXEFILE=%OUTBASE%.exe"

REM ── Locate nurlc.exe ─────────────────────────────────────────
set "SCRIPTDIR=%~dp0"
set "NURLC=%SCRIPTDIR%build\nurlc.exe"
if not exist "%NURLC%" (
    REM Fall back to old location for backwards compatibility
    set "NURLC=%SCRIPTDIR%nurlc.exe"
    if not exist "%NURLC%" (
        REM Fall back to nurlc.exe on PATH
        where nurlc.exe >nul 2>&1
        if !errorlevel! neq 0 (
            echo ERROR: nurlc.exe not found in build\, next to this script, or in PATH
            echo        Run build.bat first to build nurlc.exe
            exit /b 1
        )
        set "NURLC=nurlc.exe"
    )
)

REM ── Pick the compiler: bundled zig (preferred) or system clang ──
REM The Windows archive ships a zig at <prefix>\zig\zig.exe, exactly as
REM the Linux one does, but this driver used to look only for clang — so
REM a blank Windows box with no system LLVM could not build a program
REM natively even though the compiler it needed was sitting in the
REM install. Prefer the bundled zig, fall back to clang.
REM
REM CC_OPT_FIX: `zig cc` drops the -O level for LLVM IR inputs. It
REM forwards it for C (`zig cc -O2 -c x.c` reaches cc1 as -O2) but for a
REM `.ll` it passes nothing and cc1 defaults to -O0 — and NURL compiles
REM to `.ll`. `-Xclang <level>` goes straight to cc1 and survives. See
REM the same handling in nurl.sh.
set "CLANG=clang"
if exist "C:\Program Files\LLVM\bin\clang.exe" (
    set "CLANG=C:\Program Files\LLVM\bin\clang.exe"
)
set "ZIG_BIN=%NURL_ZIG%"
if "%ZIG_BIN%"=="" set "ZIG_BIN=%SCRIPTDIR%zig\zig.exe"
set "USING_ZIG=0"
REM The quotes live INSIDE the variable: an install path with a space
REM (C:\Users\First Last\.nurl\) otherwise splits the command.
if exist "%ZIG_BIN%" (
    set "USING_ZIG=1"
    set "CC="%ZIG_BIN%" cc"
) else (
    set "CC="%CLANG%""
)

REM ── Locate the runtime object matching that compiler's ABI ───
REM Windows has two, and they are not interchangeable. runtime.o is
REM clang-built, so MSVC-ABI: it references _setjmp, __chkstk and
REM _fltused, none of which MinGW's CRT provides. The zig above targets
REM x86_64-windows-gnu, so linking it against runtime.o fails on exactly
REM those three. build.bat builds stdlib\runtime.mingw.o with zig for
REM this path; pick whichever object matches the compiler chosen above.
set "RUNTIME=%SCRIPTDIR%stdlib\runtime.o"
set "MINGW_ABI=0"
if "%USING_ZIG%"=="1" (
    if exist "%SCRIPTDIR%stdlib\runtime.mingw.o" (
        set "RUNTIME=%SCRIPTDIR%stdlib\runtime.mingw.o"
        set "MINGW_ABI=1"
    ) else (
        REM Built on a box with no zig, so no MinGW runtime was produced.
        REM clang's ABI matches the object we do have — use it rather than
        REM emitting a link that cannot possibly resolve.
        "%CLANG%" --version >nul 2>&1
        if errorlevel 1 (
            echo ERROR: the bundled zig needs stdlib\runtime.mingw.o, which this
            echo        toolchain does not carry, and no clang was found either.
            echo        Rebuild with build.bat on a box that has zig, or install
            echo        LLVM ^(https://releases.llvm.org^) to link with clang.
            exit /b 1
        )
        set "USING_ZIG=0"
        set "CC="%CLANG%""
    )
)
if not exist "%RUNTIME%" (
    echo ERROR: !RUNTIME! not found
    echo        Run build.bat to build the NURL stdlib first.
    exit /b 1
)

REM ── Step 1: .nu → LLVM IR ────────────────────────────────────
if "%EMIT_IR%"=="1" (
    echo [1/1] %SRCFILE% → %LLFILE%
) else (
    echo [1/2] %SRCFILE% → %LLFILE%
)
"%NURLC%" "%SRCFILE%" > "%LLFILE%"
if !errorlevel! neq 0 (
    if exist "%LLFILE%" del "%LLFILE%"
    echo ERROR: NURL compilation failed
    exit /b 1
)

if "%EMIT_IR%"=="1" (
    echo.
    echo Done: %LLFILE%
    endlocal
    exit /b 0
)

REM ── Step 2: LLVM IR → native binary (or .s with --emit-asm) ──
REM nurlc emits `alloca` inside loop bodies (not entry blocks), so at -O0
REM each loop iteration leaks a stack slot and long-running programs
REM overflow the default stack. -O2 runs mem2reg which hoists them out;
REM override with `set NURL_OPT=-O0` or `-O0` CLI flag when debugging.
if defined CLI_OPT (
    set "NURL_OPT=%CLI_OPT%"
) else if "%NURL_OPT%"=="" (
    set "NURL_OPT=-O2"
)

REM zig needs the level restated for cc1 (see the CC selection above).
set "CC_OPT_FIX="
if "%USING_ZIG%"=="1" set "CC_OPT_FIX=-Xclang %NURL_OPT%"

REM Debug flag passthrough. With no `!dbg` metadata in the IR, `-g` yields
REM only crude line info from the inlined .ll filename; still useful in
REM debuggers for frame isolation and symbol demangling.
set "DEBUG_FLAG="
if "%DEBUG_INFO%"=="1" set "DEBUG_FLAG=-g"

REM --emit-asm: stop after clang -S, skip linking.
if "%EMIT_ASM%"=="1" (
    echo [2/2] %LLFILE% → %SFILE%  ^(%NURL_OPT% %DEBUG_FLAG% -S^)
    %CC% %NURL_OPT% %CC_OPT_FIX% %DEBUG_FLAG% -S "%LLFILE%" -o "%SFILE%"
    if !errorlevel! neq 0 (
        echo ERROR: -S step failed
        exit /b 1
    )
    echo.
    echo Done: %SFILE%
    endlocal
    exit /b 0
)

REM Auto-link canvas.o + SDL2 when the program references canvas_* FFI.
set "EXTRA_OBJS="
set "EXTRA_LIBS="
set "SDL2_LIBDIR="
set "SDL2_BINDIR="
findstr /R /C:"@canvas_open\>" /C:"@canvas_present\>" /C:"@canvas_sleep\>" /C:"@canvas_should_close\>" /C:"@canvas_close\>" /C:"@canvas_mouse_x\>" /C:"@canvas_mouse_y\>" /C:"@canvas_mouse_btn\>" "%LLFILE%" >nul 2>&1
if not errorlevel 1 (
    REM canvas.o is clang-built and SDL2.lib is an MSVC import lib, so
    REM neither can go into a MinGW image. Say so here rather than let the
    REM linker report it as a pile of undefined symbols.
    if "!MINGW_ABI!"=="1" (
        echo ERROR: this program uses the canvas FFI, which needs canvas.o and
        echo        SDL2 — both MSVC-ABI, while the bundled zig links MinGW.
        echo        Build it with clang instead: install LLVM and re-run with
        echo        NURL_ZIG set to a path that does not exist, e.g.
        echo            set NURL_ZIG=none
        exit /b 1
    )
    set "CANVAS_O=%SCRIPTDIR%stdlib\canvas.o"
    if not exist "!CANVAS_O!" (
        echo ERROR: program uses canvas FFI but !CANVAS_O! is missing.
        echo        Run build.bat to build the NURL stdlib first.
        exit /b 1
    )
    set "EXTRA_OBJS=!CANVAS_O!"
    REM Was canvas.o compiled with the real SDL2 back-end? build.bat
    REM drops a marker file next to canvas.o in that case. On a stub
    REM build we link *without* -lSDL2 — the exe runs fine, and any
    REM canvas_* call prints a clear diagnostic and exits.
    if exist "%SCRIPTDIR%stdlib\canvas.sdl2" (
        REM Locate SDL2.lib + SDL2.dll. vcpkg's x64-windows triplet keeps the
        REM import library under `lib\` and the DLL under `bin\`.
        if exist "C:\SDL2\lib\SDL2.lib" (
            set "SDL2_LIBDIR=C:\SDL2\lib"
            if exist "C:\SDL2\lib\SDL2.dll"  set "SDL2_BINDIR=C:\SDL2\lib"
            if exist "C:\SDL2\bin\SDL2.dll"  set "SDL2_BINDIR=C:\SDL2\bin"
        )
        if not defined SDL2_LIBDIR if exist "%VCPKG_ROOT%\installed\x64-windows\lib\SDL2.lib" (
            set "SDL2_LIBDIR=%VCPKG_ROOT%\installed\x64-windows\lib"
            set "SDL2_BINDIR=%VCPKG_ROOT%\installed\x64-windows\bin"
        )
        if not defined SDL2_LIBDIR if exist "C:\vcpkg\installed\x64-windows\lib\SDL2.lib" (
            set "SDL2_LIBDIR=C:\vcpkg\installed\x64-windows\lib"
            set "SDL2_BINDIR=C:\vcpkg\installed\x64-windows\bin"
        )
        if not defined SDL2_LIBDIR (
            echo ERROR: canvas.o was built with SDL2 but SDL2.lib is no longer
            echo        available. Re-install SDL2 or re-run build.bat.
            exit /b 1
        )
        set "EXTRA_LIBS=-L"!SDL2_LIBDIR!" -lSDL2"
    ) else (
        echo [info] canvas.o is a stub build ^(no SDL2 at build time^).
        echo        Program will compile and link, but any canvas_* call
        echo        will abort at runtime with a diagnostic.
    )
)

REM Auto-link the FFI libs build.bat detected (issue #229). These are for
REM programs whose own IR declares the zstd FFI (stdlib\ext\compress.nu);
REM the runtime itself no longer needs them, since gzip/deflate became
REM pure NURL in §8 P6 and -DNURL_HAVE_ZLIB stopped meaning anything.
REM   - A shipped toolchain carries the static libs in stdlib\winlib\ plus a
REM     relocatable fragment (winlibs.reloc) whose $NURL_LIB$ placeholder is
REM     resolved against THIS prefix — self-contained, no vcpkg on the box.
REM   - An in-repo build with no winlib\ falls back to the build-time
REM     runtime.winlibs (its vcpkg -L"<dir>" paths are valid locally).
set "WINLIBS="
if exist "%SCRIPTDIR%stdlib\winlib\winlibs.reloc" (
    set /p WINLIBS=<"%SCRIPTDIR%stdlib\winlib\winlibs.reloc"
    set "WINLIBS=!WINLIBS:$NURL_LIB$=%SCRIPTDIR%stdlib\winlib!"
) else if exist "%SCRIPTDIR%stdlib\runtime.winlibs" (
    set /p WINLIBS=<"%SCRIPTDIR%stdlib\runtime.winlibs"
)
REM Those are vcpkg's MSVC static libs, which cannot go into a MinGW
REM image. Nothing in the runtime references them (gzip/deflate have been
REM pure NURL since §8 P6 — stdlib\std\deflate.nu), so dropping them
REM leaves no dangling symbol here. What it does cost is a program that
REM declares the zstd FFI itself (stdlib\ext\compress.nu's `& `zstd``):
REM that one needs the import lib and so needs clang. It fails at link
REM naming ZSTD_compress, which is at least a symbol worth searching for.
if "!MINGW_ABI!"=="1" set "WINLIBS="
if defined WINLIBS set "EXTRA_LIBS=!EXTRA_LIBS! !WINLIBS!"

REM System import libs. The whole of runtime.o is linked in, so every
REM program needs the libraries behind every OS bridge it contains, even
REM one that imports none of them:
REM   winhttp  — the HTTP client (stdlib/runtime.c §14)
REM   ws2_32   — the TCP/socket layer
REM   bcrypt, advapi32 — the OS-entropy bridge (BCryptGenRandom)
REM Under clang's MSVC target the last three arrive on their own, via the
REM `#pragma comment(lib, ...)` directives in runtime_ffi.c. Under MinGW —
REM which is what `zig cc` targets — those directives cannot be satisfied
REM (they name bcrypt.lib, and lld-link goes looking for libbcrypt.a), so
REM they are compiled out there and the libs must be named here instead.
REM Naming them is harmless for clang: they are all in the Windows SDK.
REM This is the same set, for the same reason, as the mingw-w64 cross link
REM in nurlapi/main.nu.
echo [2/2] %LLFILE% → %EXEFILE%  (%NURL_OPT% %DEBUG_FLAG% %EXTRA_LIBS%)
%CC% %NURL_OPT% %CC_OPT_FIX% %DEBUG_FLAG% "%LLFILE%" "%RUNTIME%" %EXTRA_OBJS% -o "%EXEFILE%" %EXTRA_LIBS% -lwinhttp -lws2_32 -lbcrypt -ladvapi32
if !errorlevel! neq 0 (
    echo ERROR: clang linking failed
    exit /b 1
)

REM Copy SDL2.dll next to the produced exe so it runs without PATH tweaks.
if defined SDL2_BINDIR if exist "%SDL2_BINDIR%\SDL2.dll" (
    for %%F in ("%EXEFILE%") do set "EXEDIR=%%~dpF"
    if not exist "!EXEDIR!SDL2.dll" copy /Y "%SDL2_BINDIR%\SDL2.dll" "!EXEDIR!" >nul
)

echo.
echo Done: %EXEFILE%
endlocal

goto :eof

:show_version
set "SDIR=%~dp0"
if exist "%SDIR%build\nurlc.exe" (
    "%SDIR%build\nurlc.exe" --version
) else (
    nurlc.exe --version
)
exit /b %ERRORLEVEL%

:do_upgrade
set "SDIR=%~dp0"
shift
set "PKGARGS="
:collect_upgrade_args
if not "%~1"=="" (
    set "PKGARGS=!PKGARGS! %~1"
    shift
    goto collect_upgrade_args
)
if exist "%SDIR%bin\nurlpkg.bat" (
    call "%SDIR%bin\nurlpkg.bat" self-update !PKGARGS!
) else if exist "%SDIR%build\nurlpkg.exe" (
    "%SDIR%build\nurlpkg.exe" self-update !PKGARGS!
) else (
    nurlpkg self-update !PKGARGS!
)
exit /b %ERRORLEVEL%
