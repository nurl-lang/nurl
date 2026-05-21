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

REM ── Locate clang ─────────────────────────────────────────────
set "CLANG=clang"
if exist "C:\Program Files\LLVM\bin\clang.exe" (
    set "CLANG=C:\Program Files\LLVM\bin\clang.exe"
)

REM ── Locate runtime.o ─────────────────────────────────────────
set "RUNTIME=%SCRIPTDIR%stdlib\runtime.o"
if not exist "%RUNTIME%" (
    echo ERROR: stdlib\runtime.o not found at %RUNTIME%
    echo        Run: build.bat
    exit /b 1
)

REM ── Locate or build nurl-build.exe ──────────────────────────
set "NURLBUILD=%SCRIPTDIR%build\nurl-build.exe"
if not exist "%NURLBUILD%" (
    if defined NURL_ZIG (
        set "ZIG=%NURL_ZIG%"
    ) else (
        set "ZIG=zig"
    )
    where "%ZIG%" >nul 2>&1
    if not errorlevel 1 (
        if not exist "%SCRIPTDIR%build" mkdir "%SCRIPTDIR%build"
        "%ZIG%" build-exe "%SCRIPTDIR%tools\nurl-build\main.zig" -O ReleaseSafe -femit-bin="%NURLBUILD%" >nul 2>&1
    )
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

REM Debug flag passthrough. With no `!dbg` metadata in the IR, `-g` yields
REM only crude line info from the inlined .ll filename; still useful in
REM debuggers for frame isolation and symbol demangling.
set "DEBUG_FLAG="
if "%DEBUG_INFO%"=="1" set "DEBUG_FLAG=-g"

REM --emit-asm: stop after clang -S, skip linking.
if "%EMIT_ASM%"=="1" (
    echo [2/2] %LLFILE% → %SFILE%  ^(%NURL_OPT% %DEBUG_FLAG% -S^)
    "%CLANG%" %NURL_OPT% %DEBUG_FLAG% -S "%LLFILE%" -o "%SFILE%"
    if !errorlevel! neq 0 (
        echo ERROR: clang -S failed
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

REM The runtime's HTTP client uses WinHTTP on Windows (stdlib/runtime.c §14),
REM so every program linked against runtime.o needs winhttp.lib even if it
REM doesn't import stdlib/ext/http.nu — unreferenced functions still end up
REM in runtime.o and their WinHttp* calls must resolve at link time.
if exist "%NURLBUILD%" (
    echo [2/2] %LLFILE% → %EXEFILE%  (%NURL_OPT% %DEBUG_FLAG% %EXTRA_LIBS% via nurl-build)
    if defined EXTRA_OBJS (
        if defined SDL2_LIBDIR (
            if defined DEBUG_FLAG (
                "%NURLBUILD%" --opt "%NURL_OPT%" --flag "%DEBUG_FLAG%" --extra-obj "!CANVAS_O!" --extra-lib "-L!SDL2_LIBDIR!" --extra-lib "-lSDL2" "%SCRIPTDIR%" "%LLFILE%" "%EXEFILE%"
            ) else (
                "%NURLBUILD%" --opt "%NURL_OPT%" --extra-obj "!CANVAS_O!" --extra-lib "-L!SDL2_LIBDIR!" --extra-lib "-lSDL2" "%SCRIPTDIR%" "%LLFILE%" "%EXEFILE%"
            )
        ) else (
            if defined DEBUG_FLAG (
                "%NURLBUILD%" --opt "%NURL_OPT%" --flag "%DEBUG_FLAG%" --extra-obj "!CANVAS_O!" "%SCRIPTDIR%" "%LLFILE%" "%EXEFILE%"
            ) else (
                "%NURLBUILD%" --opt "%NURL_OPT%" --extra-obj "!CANVAS_O!" "%SCRIPTDIR%" "%LLFILE%" "%EXEFILE%"
            )
        )
    ) else (
        if defined DEBUG_FLAG (
            "%NURLBUILD%" --opt "%NURL_OPT%" --flag "%DEBUG_FLAG%" "%SCRIPTDIR%" "%LLFILE%" "%EXEFILE%"
        ) else (
            "%NURLBUILD%" --opt "%NURL_OPT%" "%SCRIPTDIR%" "%LLFILE%" "%EXEFILE%"
        )
    )
    if !errorlevel! neq 0 (
        echo ERROR: nurl-build linking failed
        exit /b 1
    )
) else (
    echo [2/2] %LLFILE% → %EXEFILE%  (%NURL_OPT% %DEBUG_FLAG% %EXTRA_LIBS%)
    "%CLANG%" %NURL_OPT% %DEBUG_FLAG% "%LLFILE%" "%RUNTIME%" %EXTRA_OBJS% -o "%EXEFILE%" %EXTRA_LIBS% -lwinhttp
    if !errorlevel! neq 0 (
        echo ERROR: clang linking failed
        exit /b 1
    )
)

REM Copy SDL2.dll next to the produced exe so it runs without PATH tweaks.
if defined SDL2_BINDIR if exist "%SDL2_BINDIR%\SDL2.dll" (
    for %%F in ("%EXEFILE%") do set "EXEDIR=%%~dpF"
    if not exist "!EXEDIR!SDL2.dll" copy /Y "%SDL2_BINDIR%\SDL2.dll" "!EXEDIR!" >nul
)

echo.
echo Done: %EXEFILE%
endlocal
