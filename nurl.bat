@echo off
setlocal DisableDelayedExpansion

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
REM    --no-borrowck        Forwarded to nurlc: bypass the borrow checker
REM    --strict-borrowck    Forwarded to nurlc: the opt-in extra checks
REM    --strict-arity /     Forwarded to nurlc: n-ary `&`/`|` arity trap
REM    --no-strict-arity      as error (default) / warning
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
set "NURLC_DIAG="

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
if /i "%~1"=="--emit-ir"  ( set "EMIT_IR=1"     & shift & goto parse_flags )
if /i "%~1"=="--emit=ir"  ( set "EMIT_IR=1"     & shift & goto parse_flags )
if /i "%~1"=="--emit-asm" ( set "EMIT_ASM=1"    & shift & goto parse_flags )
if /i "%~1"=="--emit=asm" ( set "EMIT_ASM=1"    & shift & goto parse_flags )
if /i "%~1"=="-g"         ( set "DEBUG_INFO=1"  & shift & goto parse_flags )
if /i "%~1"=="--debug"    ( set "DEBUG_INFO=1"  & shift & goto parse_flags )
if /i "%~1"=="-O0"        ( set "CLI_OPT=-O0"   & shift & goto parse_flags )
if /i "%~1"=="-O1"        ( set "CLI_OPT=-O1"   & shift & goto parse_flags )
if /i "%~1"=="-O2"        ( set "CLI_OPT=-O2"   & shift & goto parse_flags )
if /i "%~1"=="-O3"        ( set "CLI_OPT=-O3"   & shift & goto parse_flags )
REM Diagnostic flags forwarded verbatim — `--no-borrowck` is what the
REM compiler's own borrow-checker error tells the user to re-run with,
REM and without this it was read as the source file name.
if /i "%~1"=="--no-borrowck"     ( set "NURLC_DIAG=%NURLC_DIAG% --no-borrowck"     & shift & goto parse_flags )
if /i "%~1"=="--strict-borrowck" ( set "NURLC_DIAG=%NURLC_DIAG% --strict-borrowck" & shift & goto parse_flags )
if /i "%~1"=="--strict-arity"    ( set "NURLC_DIAG=%NURLC_DIAG% --strict-arity"    & shift & goto parse_flags )
if /i "%~1"=="--no-strict-arity" ( set "NURLC_DIAG=%NURLC_DIAG% --no-strict-arity" & shift & goto parse_flags )

if "%~1"=="" (
    echo Usage: nurl.bat [flags] ^<file.nu^> [output_name]
    echo.
    echo  Flags: --emit-ir ^| --emit-asm ^| -O0..-O3 ^| -g ^| --debug
    echo         --no-borrowck ^| --strict-borrowck ^| --strict-arity ^| --no-strict-arity
    echo.
    echo  Compiles a NURL source file to a native Windows executable.
    echo.
    echo  nurl --version ^| -v         Print the toolchain version.
    echo  nurl upgrade [--check]      Upgrade the toolchain in place.
    echo  The intermediate .ll file is kept alongside the output.
    exit /b 1
)

set "SRCFILE=%~f1"

REM ── Derive output names ──────────────────────────────────────
if "%~2"=="" (
    set "OUTBASE=%~n1"
) else (
    set "OUTBASE=%~2"
)
for %%I in ("%OUTBASE%") do set "OUTBASE=%%~fI"
for %%I in ("%OUTBASE%") do set "EXEDIR=%%~dpI"
for %%I in ("%OUTBASE%") do set "OUTNAME=%%~nxI"
set "SCRIPTDIR=%~dp0"
REM Values inserted through delayed expansion are not parsed as command
REM operators and their embedded ! characters are not expanded again.
setlocal EnableDelayedExpansion
if not defined NURL_STDLIB set "NURL_STDLIB=!SCRIPTDIR!"
if not exist "!SRCFILE!" (
    echo ERROR: Source file not found: !SRCFILE!
    exit /b 1
)
set "LLFILE=!OUTBASE!.ll"
set "SFILE=!OUTBASE!.s"
set "EXEFILE=!OUTBASE!.exe"

REM ── Locate nurlc.exe ─────────────────────────────────────────
set "NURLC=!SCRIPTDIR!build\nurlc.exe"
if not exist "!NURLC!" (
    REM Fall back to old location for backwards compatibility
    set "NURLC=!SCRIPTDIR!nurlc.exe"
    if not exist "!NURLC!" (
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
set "ZIG_BIN=!NURL_ZIG!"
if "!ZIG_BIN!"=="" set "ZIG_BIN=!SCRIPTDIR!zig\zig.exe"
set "USING_ZIG=0"
REM The quotes live INSIDE the variable: an install path with a space
REM (C:\Users\First Last\.nurl\) otherwise splits the command.
if exist "!ZIG_BIN!" (
    set "USING_ZIG=1"
    set "CC="!ZIG_BIN!" cc"
) else (
    set "CC="!CLANG!""
)

REM ── Locate the runtime object matching that compiler's ABI ───
REM Windows has two, and they are not interchangeable. runtime.o is
REM clang-built, so MSVC-ABI: it references _setjmp, __chkstk and
REM _fltused, none of which MinGW's CRT provides. The zig above targets
REM x86_64-windows-gnu, so linking it against runtime.o fails on exactly
REM those three. build.bat builds stdlib\runtime.mingw.o with zig for
REM this path; pick whichever object matches the compiler chosen above.
set "RUNTIME=!SCRIPTDIR!stdlib\runtime.o"
set "MINGW_ABI=0"
if "!USING_ZIG!"=="1" (
    if exist "!SCRIPTDIR!stdlib\runtime.mingw.o" (
        set "RUNTIME=!SCRIPTDIR!stdlib\runtime.mingw.o"
        set "MINGW_ABI=1"
    ) else (
        REM Built on a box with no zig, so no MinGW runtime was produced.
        REM clang's ABI matches the object we do have — use it rather than
        REM emitting a link that cannot possibly resolve.
        "!CLANG!" --version >nul 2>&1
        if errorlevel 1 (
            echo ERROR: the bundled zig needs stdlib\runtime.mingw.o, which this
            echo        toolchain does not carry, and no clang was found either.
            echo        Rebuild with build.bat on a box that has zig, or install
            echo        LLVM ^(https://releases.llvm.org^) to link with clang.
            exit /b 1
        )
        set "USING_ZIG=0"
        set "CC="!CLANG!""
    )
)
if not exist "!RUNTIME!" (
    echo ERROR: !RUNTIME! not found
    echo        Run build.bat to build the NURL stdlib first.
    exit /b 1
)

REM ── Step 1: .nu → LLVM IR ────────────────────────────────────
if "!EMIT_IR!"=="1" (
    echo [1/1] !SRCFILE! → !LLFILE!
) else (
    echo [1/2] !SRCFILE! → !LLFILE!
)
set "NURLC_G="
if "!DEBUG_INFO!"=="1" set "NURLC_G=--g"
"!NURLC!" !NURLC_G!!NURLC_DIAG! "!SRCFILE!" > "!LLFILE!"
if !errorlevel! neq 0 (
    if exist "!LLFILE!" del "!LLFILE!"
    echo ERROR: NURL compilation failed
    exit /b 1
)

if "!EMIT_IR!"=="1" (
    echo.
    echo Done: !LLFILE!
    endlocal
    exit /b 0
)

REM ── Step 2: LLVM IR → native binary (or .s with --emit-asm) ──
REM nurlc emits `alloca` inside loop bodies (not entry blocks), so at -O0
REM each loop iteration leaks a stack slot and long-running programs
REM overflow the default stack. -O2 runs mem2reg which hoists them out;
REM override with `set NURL_OPT=-O0` or `-O0` CLI flag when debugging.
if defined CLI_OPT (
    set "NURL_OPT=!CLI_OPT!"
) else if "!NURL_OPT!"=="" (
    set "NURL_OPT=-O2"
)

REM zig needs the level restated for cc1 (see the CC selection above).
set "CC_OPT_FIX="
if "!USING_ZIG!"=="1" set "CC_OPT_FIX=-Xclang !NURL_OPT!"

REM The frontend emits source locations above; clang preserves them in
REM the native object when debug information was requested.
set "DEBUG_FLAG="
if "!DEBUG_INFO!"=="1" set "DEBUG_FLAG=-g"

REM --emit-asm: stop after clang -S, skip linking.
if "!EMIT_ASM!"=="1" (
    echo [2/2] !LLFILE! → !SFILE!  ^(!NURL_OPT! !DEBUG_FLAG! -S^)
    !CC! !NURL_OPT! !CC_OPT_FIX! !DEBUG_FLAG! -S "!LLFILE!" -o "!SFILE!"
    if !errorlevel! neq 0 (
        echo ERROR: -S step failed
        exit /b 1
    )
    echo.
    echo Done: !SFILE!
    endlocal
    exit /b 0
)

REM Auto-link canvas.o + SDL2 when the program references canvas_* FFI.
set "EXTRA_OBJS="
set "EXTRA_LIBS="
set "SDL2_LIBDIR="
set "SDL2_BINDIR="
findstr /R /C:"@canvas_open\>" /C:"@canvas_present\>" /C:"@canvas_sleep\>" /C:"@canvas_should_close\>" /C:"@canvas_close\>" /C:"@canvas_mouse_x\>" /C:"@canvas_mouse_y\>" /C:"@canvas_mouse_btn\>" "!LLFILE!" >nul 2>&1
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
    set "CANVAS_O=!SCRIPTDIR!stdlib\canvas.o"
    if not exist "!CANVAS_O!" (
        echo ERROR: program uses canvas FFI but !CANVAS_O! is missing.
        echo        Run build.bat to build the NURL stdlib first.
        exit /b 1
    )
    set EXTRA_OBJS="!CANVAS_O!"
    REM Was canvas.o compiled with the real SDL2 back-end? build.bat
    REM drops a marker file next to canvas.o in that case. On a stub
    REM build we link *without* -lSDL2 — the exe runs fine, and any
    REM canvas_* call prints a clear diagnostic and exits.
    if exist "!SCRIPTDIR!stdlib\canvas.sdl2" (
        REM Locate SDL2.lib + SDL2.dll. vcpkg's x64-windows triplet keeps the
        REM import library under `lib\` and the DLL under `bin\`.
        if exist "C:\SDL2\lib\SDL2.lib" (
            set "SDL2_LIBDIR=C:\SDL2\lib"
            if exist "C:\SDL2\lib\SDL2.dll"  set "SDL2_BINDIR=C:\SDL2\lib"
            if exist "C:\SDL2\bin\SDL2.dll"  set "SDL2_BINDIR=C:\SDL2\bin"
        )
        if not defined SDL2_LIBDIR if exist "!VCPKG_ROOT!\installed\x64-windows\lib\SDL2.lib" (
            set "SDL2_LIBDIR=!VCPKG_ROOT!\installed\x64-windows\lib"
            set "SDL2_BINDIR=!VCPKG_ROOT!\installed\x64-windows\bin"
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

REM ── Auto-link the CUDA Driver API + NVRTC ────────────────────
REM Mirrors nurl.sh §"Auto-link the CUDA Driver API (libcuda) and NVRTC".
REM packages\gpu binds the driver (& `cuda` @ cu…) and NVRTC
REM (& `nvrtc` @ nvrtc…) directly, with no runtime.c bridge, so those ~40
REM symbols must come from somewhere at link time or lld reports every one
REM as undefined. Two sources:
REM   - a CUDA Toolkit (cuda.lib + nvrtc.lib under !CUDA_PATH!\lib\x64) —
REM     GPU compute runs for real. Both are needed: packages\gpu has no
REM     precompiled kernels, it feeds CUDA-C through NVRTC at runtime
REM     (cuda_compile → PTX/CUBIN → cuModuleLoadData), so the driver alone
REM     buys nothing. The driver's own nvcuda.dll is NOT a substitute: it
REM     ships no NVRTC, and its export directory names itself
REM     `nvcuda_loader.dll`, so linking the DLL directly yields an import of
REM     a file that does not exist and the exe dies at load with a missing-
REM     DLL error rather than anything diagnosable.
REM   - the fallback stubs (stdlib\{cuda,nvrtc}_stubs.c) otherwise: the
REM     program links and loads, every CUDA call returns a non-zero
REM     CUresult, and gpu_open falls back to the CPU backend
REM     (packages\gpu\src\cpu.nu). This is the path a package that only
REM     pulls in gpu transitively — anomaly → tensor → gpukit → gpu — takes,
REM     and it wants no GPU at all.
REM The stubs go in as SOURCE rather than a prebuilt object because this
REM script links MSVC-ABI under clang and MinGW-ABI under the bundled zig;
REM handing !CC! the .c compiles the translation unit with whichever ABI
REM this particular link is using, so one file serves both.
REM `set NURL_GPU_STUBS=1` forces the stub path (same knob as nurl.sh).
set "CUDA_LIBDIR="
if not defined NURL_GPU_STUBS if defined CUDA_PATH if exist "!CUDA_PATH!\lib\x64\nvrtc.lib" (
    REM Those are MSVC import libs, so they can only go into an MSVC-ABI
    REM image — the same constraint canvas.o + SDL2.lib carry above. Under
    REM the bundled zig, say so and fall through to the stubs rather than
    REM emit a link the user cannot act on.
    if "!MINGW_ABI!"=="1" (
        echo [info] CUDA Toolkit found, but its import libs are MSVC-ABI and the
        echo        bundled zig links MinGW — using the CPU-fallback stubs. For real
        echo        GPU compute, build with clang instead: install LLVM and re-run
        echo        with NURL_ZIG pointing at a path that does not exist, e.g.
        echo            set NURL_ZIG=none
    ) else (
        set "CUDA_LIBDIR=!CUDA_PATH!\lib\x64"
    )
)
findstr /R /C:"@cu[A-Z]" "!LLFILE!" >nul 2>&1
if not errorlevel 1 (
    if defined CUDA_LIBDIR (
        set EXTRA_LIBS=!EXTRA_LIBS! -L"!CUDA_LIBDIR!" -lcuda
        echo [info] CUDA driver linked from "!CUDA_LIBDIR!"
    ) else (
        if not exist "!SCRIPTDIR!stdlib\cuda_stubs.c" (
            echo ERROR: program uses the CUDA FFI but !SCRIPTDIR!stdlib\cuda_stubs.c
            echo        is missing. Run build.bat to build the NURL stdlib first.
            exit /b 1
        )
        set EXTRA_OBJS=!EXTRA_OBJS! "!SCRIPTDIR!stdlib\cuda_stubs.c"
        echo [info] no linkable CUDA Toolkit - cu* uses stubs; packages\gpu runs on the CPU
    )
)
findstr /R /C:"@nvrtc[A-Z]" "!LLFILE!" >nul 2>&1
if not errorlevel 1 (
    if defined CUDA_LIBDIR (
        set EXTRA_LIBS=!EXTRA_LIBS! -lnvrtc
    ) else (
        if not exist "!SCRIPTDIR!stdlib\nvrtc_stubs.c" (
            echo ERROR: program uses the NVRTC FFI but !SCRIPTDIR!stdlib\nvrtc_stubs.c
            echo        is missing. Run build.bat to build the NURL stdlib first.
            exit /b 1
        )
        set EXTRA_OBJS=!EXTRA_OBJS! "!SCRIPTDIR!stdlib\nvrtc_stubs.c"
    )
)

REM ── Win32 dynamic-loader shims (dlopen / dlsym / dlclose) ────
REM packages\gpu's CPU backend binds the POSIX loader (& `c` @ dlopen …) to
REM load the host object it JIT-builds its kernels into. Those three symbols
REM are in libdl/libc on any POSIX host, so nurl.sh needs no equivalent of
REM this block; Windows has none of them, and a program that merely IMPORTS
REM packages\gpu — anomaly → tensor → gpukit → gpu, none of which asks for a
REM GPU — died with "undefined symbol: dlopen" out of cpu_compile. Compile
REM the LoadLibraryA forwarders in when the IR reaches for them. Source, not
REM an object, for the same ABI reason as the CUDA stubs above.
findstr /R /C:"@dlopen\>" /C:"@dlsym\>" /C:"@dlclose\>" "!LLFILE!" >nul 2>&1
if not errorlevel 1 (
    if not exist "!SCRIPTDIR!stdlib\dl_win32.c" (
        echo ERROR: program uses the POSIX dynamic loader ^(dlopen/dlsym/dlclose^)
        echo        but !SCRIPTDIR!stdlib\dl_win32.c is missing. Run build.bat
        echo        to build the NURL stdlib first.
        exit /b 1
    )
    set EXTRA_OBJS=!EXTRA_OBJS! "!SCRIPTDIR!stdlib\dl_win32.c"
)

REM Auto-link the FFI libs build.bat detected (issue #229). These are for
REM programs whose own IR declares an FFI; the runtime itself no longer
REM needs them, since gzip/deflate became pure NURL in §8 P6 and zstd in
REM stdlib\std\zstd.nu.
REM   - A shipped toolchain carries the static libs in stdlib\winlib\ plus a
REM     relocatable fragment (winlibs.reloc) whose $NURL_LIB$ placeholder is
REM     resolved against THIS prefix — self-contained, no vcpkg on the box.
REM   - An in-repo build with no winlib\ falls back to the build-time
REM     runtime.winlibs (its vcpkg -L"<dir>" paths are valid locally).
set "WINLIBS="
if exist "!SCRIPTDIR!stdlib\winlib\winlibs.reloc" (
    set /p WINLIBS=<"!SCRIPTDIR!stdlib\winlib\winlibs.reloc"
    set "WINLIBS=!WINLIBS:$NURL_LIB$=.\stdlib\winlib!"
) else if exist "!SCRIPTDIR!stdlib\runtime.winlibs" (
    set /p WINLIBS=<"!SCRIPTDIR!stdlib\runtime.winlibs"
)
REM Those are vcpkg's MSVC static libs, which cannot go into a MinGW
REM image. Nothing in the runtime references them (gzip/deflate have been
REM pure NURL since §8 P6 — stdlib\std\deflate.nu, and zstd likewise in
REM stdlib\std\zstd.nu), so dropping them leaves no dangling symbol here.
REM A program that declares some OTHER vcpkg FFI itself still needs the
REM import lib, and so still needs clang.
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
echo [2/2] !LLFILE! → !EXEFILE!  (!NURL_OPT! !DEBUG_FLAG! !EXTRA_LIBS!)
set "LINK_TRIES=0"
:allocate_link_dir
set /a LINK_TRIES+=1 >nul
if !LINK_TRIES! gtr 16 (
    echo ERROR: could not create an exclusive link directory
    exit /b 1
)
set "LINK_DIR=!OUTBASE!.link.!RANDOM!.!RANDOM!"
mkdir "!LINK_DIR!" >nul 2>&1
if errorlevel 1 goto allocate_link_dir
set "LINK_OUTPUT=!LINK_DIR!\!OUTNAME!.exe"
set "LINK_PDB=!LINK_DIR!\!OUTNAME!.pdb"
set "FINAL_PDB=!OUTBASE!.pdb"
set "DEBUG_LINK_FLAGS="
REM The binary records a stable adjacent PDB name, not the staging path.
REM %%_PDB%% is expanded by the MSVC linker to its PDB filename.
if "!DEBUG_INFO!"=="1" if "!MINGW_ABI!"=="0" set "DEBUG_LINK_FLAGS=-Xlinker /PDBALTPATH:%%_PDB%%"
pushd "!SCRIPTDIR!"
if errorlevel 1 (
    rmdir /s /q "!LINK_DIR!"
    exit /b 1
)
!CC! !NURL_OPT! !CC_OPT_FIX! !DEBUG_FLAG! !DEBUG_LINK_FLAGS! "!LLFILE!" "!RUNTIME!" !EXTRA_OBJS! -o "!LINK_OUTPUT!" !EXTRA_LIBS! -lwinhttp -lws2_32 -lbcrypt -ladvapi32
set "LINK_RC=!errorlevel!"
popd
if not "!LINK_RC!"=="0" (
    rmdir /s /q "!LINK_DIR!"
    echo ERROR: clang linking failed
    exit /b 1
)
if not exist "!LINK_OUTPUT!" (
    rmdir /s /q "!LINK_DIR!"
    echo ERROR: linker did not produce an executable
    exit /b 1
)
REM MOVE accepts directories as operands/destinations. Only regular files
REM may enter this transaction: otherwise cleanup could remove caller data.
REM Two traps, one on each side of the question. %%~a reports an EMPTY
REM string for anything it declines to stat, and "no attributes" is not
REM the same fact as "not a regular file" -- reading it as one rejected an
REM ordinary staged executable. And `if exist "path\"` only answers the
REM directory question for a path that EXISTS: with a trailing backslash
REM cmd resolves a missing path to its parent, so it answered yes for a
REM destination that was not there at all. Ask whether it exists first,
REM then whether the thing that exists is a directory; %%~a is left with
REM the one bit it does report reliably.
set "PUB_ATTRIBUTES="
set "PUB_SUBJECT=staged executable !LINK_OUTPUT!"
if exist "!LINK_OUTPUT!" if exist "!LINK_OUTPUT!\" goto invalid_link_artifact
for %%I in ("!LINK_OUTPUT!") do set "PUB_ATTRIBUTES=%%~aI"
if not "!PUB_ATTRIBUTES:l=!"=="!PUB_ATTRIBUTES!" goto invalid_link_artifact
set "PUB_ATTRIBUTES="
set "PUB_SUBJECT=staged debug symbols !LINK_PDB!"
if exist "!LINK_PDB!" if exist "!LINK_PDB!\" goto invalid_link_artifact
for %%I in ("!LINK_PDB!") do set "PUB_ATTRIBUTES=%%~aI"
if not "!PUB_ATTRIBUTES:l=!"=="!PUB_ATTRIBUTES!" goto invalid_link_artifact
set "PUB_ATTRIBUTES="
set "PUB_SUBJECT=destination executable !EXEFILE!"
if exist "!EXEFILE!" if exist "!EXEFILE!\" goto invalid_link_artifact
for %%I in ("!EXEFILE!") do set "PUB_ATTRIBUTES=%%~aI"
if not "!PUB_ATTRIBUTES:l=!"=="!PUB_ATTRIBUTES!" goto invalid_link_artifact
set "PUB_ATTRIBUTES="
set "PUB_SUBJECT=destination debug symbols !FINAL_PDB!"
if exist "!FINAL_PDB!" if exist "!FINAL_PDB!\" goto invalid_link_artifact
for %%I in ("!FINAL_PDB!") do set "PUB_ATTRIBUTES=%%~aI"
if not "!PUB_ATTRIBUTES:l=!"=="!PUB_ATTRIBUTES!" goto invalid_link_artifact
REM Publish the companion before its binary and restore it if either move
REM fails. A linker failure above never touches the prior binary or PDB.
set "HAD_PDB=0"
if exist "!FINAL_PDB!" (
    move /Y "!FINAL_PDB!" "!LINK_DIR!\.previous-pdb" >nul
    if errorlevel 1 (
        rmdir /s /q "!LINK_DIR!"
        echo ERROR: could not preserve prior debug symbols
        exit /b 1
    )
    set "HAD_PDB=1"
)
if exist "!LINK_PDB!" (
    move /Y "!LINK_PDB!" "!FINAL_PDB!" >nul
    if errorlevel 1 goto restore_link_pdb
)
move /Y "!LINK_OUTPUT!" "!EXEFILE!" >nul
if errorlevel 1 goto restore_link_pdb
rmdir /s /q "!LINK_DIR!"
goto link_published

:invalid_link_artifact
rmdir /s /q "!LINK_DIR!"
echo ERROR: executable and debug symbol paths must be regular files
echo ERROR: rejected !PUB_SUBJECT! ^(attributes "!PUB_ATTRIBUTES!"^)
exit /b 1

:restore_link_pdb
REM Recheck before DEL: unlike a file unlink, DEL on a directory removes
REM its contents. Preserve recovery state if a publication path changed.
set "PUB_ATTRIBUTES="
if exist "!FINAL_PDB!" if exist "!FINAL_PDB!\" goto unsafe_pdb_restore
for %%I in ("!FINAL_PDB!") do set "PUB_ATTRIBUTES=%%~aI"
if not "!PUB_ATTRIBUTES:l=!"=="!PUB_ATTRIBUTES!" goto unsafe_pdb_restore
if exist "!FINAL_PDB!" del /q "!FINAL_PDB!"
if "!HAD_PDB!"=="1" (
    move /Y "!LINK_DIR!\.previous-pdb" "!FINAL_PDB!" >nul
    if errorlevel 1 (
        echo ERROR: could not restore debug symbols; prior copy retained in !LINK_DIR!
        exit /b 1
    )
)
rmdir /s /q "!LINK_DIR!"
echo ERROR: could not publish executable and debug symbols
exit /b 1

:unsafe_pdb_restore
echo ERROR: debug symbol path changed type; recovery files retained in !LINK_DIR!
exit /b 1

:link_published
REM Copy SDL2.dll next to the produced exe so it runs without PATH tweaks.
if defined SDL2_BINDIR if exist "!SDL2_BINDIR!\SDL2.dll" (
    REM EXEDIR was captured before delayed expansion was enabled.
    if not exist "!EXEDIR!SDL2.dll" copy /Y "!SDL2_BINDIR!\SDL2.dll" "!EXEDIR!" >nul
)

echo.
echo Done: !EXEFILE!
endlocal

goto :eof

:show_version
set "SDIR=%~dp0"
setlocal EnableDelayedExpansion
if exist "!SDIR!build\nurlc.exe" (
    "!SDIR!build\nurlc.exe" --version
) else (
    nurlc.exe --version
)
exit /b !ERRORLEVEL!

:do_upgrade
set "SDIR=%~dp0"
shift
set "PKGARGS="
:collect_upgrade_args
if not "%~1"=="" (
    set PKGARGS=%PKGARGS% "%~1"
    shift
    goto collect_upgrade_args
)
if exist "%SDIR%bin\nurlpkg.bat" (
    "%SDIR%bin\nurlpkg.bat" self-update %PKGARGS%
) else if exist "%SDIR%build\nurlpkg.exe" (
    "%SDIR%build\nurlpkg.exe" self-update %PKGARGS%
) else (
    nurlpkg self-update %PKGARGS%
)
exit /b %ERRORLEVEL%
