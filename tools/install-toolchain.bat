@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM ============================================================
REM  install-toolchain.bat - Windows counterpart of
REM  install-toolchain.sh. Installs the NURL compiler + package
REM  manager + stdlib into a self-contained prefix and wires up
REM  the paths that make them work from any directory.
REM
REM  After running this and adding %NURL_HOME%\bin to PATH, `nurl`,
REM  `nurlc`, and `nurlpkg` are available everywhere, $NURL_STDLIB
REM  points at the shipped stdlib (so the compiler resolves
REM  `$ `stdlib/...`` imports from anywhere), and
REM  `nurlpkg install <name>` can fetch, build, and install
REM  programs from the registry.
REM
REM  Layout (%NURL_HOME%, default %USERPROFILE%\.nurl):
REM    %PREFIX%\build\nurlc.exe          the compiler
REM    %PREFIX%\build\nurlpkg.exe        the package manager
REM    %PREFIX%\stdlib\                  the stdlib tree (+ runtime.o)
REM    %PREFIX%\docs\                    the documentation tree (nurl_docs)
REM    %PREFIX%\nurl.bat                 the .nu -> native build driver
REM    %PREFIX%\bin\{nurl,nurlc,nurlpkg}.bat   PATH shims (set NURL_STDLIB)
REM    %PREFIX%\env.bat                  sets NURL_STDLIB + PATH for a session
REM
REM  Usage:
REM    tools\install-toolchain.bat              install to %USERPROFILE%\.nurl
REM    set NURL_HOME=C:\nurl & tools\install-toolchain.bat
REM    tools\install-toolchain.bat --uninstall
REM
REM  Windows uses copies (not symlinks) and .bat shims; otherwise the
REM  layout and behaviour mirror install-toolchain.sh exactly.
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
REM ROOT is the repo root (parent of tools\).
for %%I in ("%SCRIPT_DIR%\..") do set "ROOT=%%~fI"

if not defined NURL_HOME set "NURL_HOME=%USERPROFILE%\.nurl"
set "PREFIX=%NURL_HOME%"

if /i "%~1"=="--uninstall" goto :uninstall

REM ── Preconditions ─────────────────────────────────────────────
if not exist "%ROOT%\build\nurlc.exe"   ( echo ERROR: build\nurlc.exe missing - run build.bat first 1>&2 & exit /b 1 )
if not exist "%ROOT%\build\nurlpkg.exe" ( echo ERROR: build\nurlpkg.exe missing - run tools\nurlpkg\build.bat first 1>&2 & exit /b 1 )
if not exist "%ROOT%\stdlib\runtime.o"  ( echo ERROR: stdlib\runtime.o missing - run build.bat first 1>&2 & exit /b 1 )
if not exist "%ROOT%\nurl.bat"          ( echo ERROR: nurl.bat missing 1>&2 & exit /b 1 )

echo Installing NURL toolchain -^> %PREFIX%
if not exist "%PREFIX%\bin"   mkdir "%PREFIX%\bin"
if not exist "%PREFIX%\build" mkdir "%PREFIX%\build"
if not exist "%PREFIX%\stdlib" mkdir "%PREFIX%\stdlib"

REM Compiler + package manager.
copy /y "%ROOT%\build\nurlc.exe"   "%PREFIX%\build\nurlc.exe"   >nul
copy /y "%ROOT%\build\nurlpkg.exe" "%PREFIX%\build\nurlpkg.exe" >nul

REM Formatter (best-effort: installed when present; without it nurlfmt and the
REM nurl-mcp nurl_fmt tool are unavailable).
set "HAVE_NURLFMT=0"
if exist "%ROOT%\build\nurlfmt.exe" (
  copy /y "%ROOT%\build\nurlfmt.exe" "%PREFIX%\build\nurlfmt.exe" >nul
  set "HAVE_NURLFMT=1"
) else (
  echo Note: build\nurlfmt.exe absent - skipping ^(run build.bat to build it^).
)

REM Stdlib tree (incl. runtime.o, runtime.<feature> link sentinels, canvas.o).
xcopy /e /i /y /q "%ROOT%\stdlib" "%PREFIX%\stdlib" >nul

REM Documentation tree - what the nurl-mcp nurl_docs tool serves
REM (%NURL_STDLIB%\docs, i.e. right here). Text only, a few hundred KB.
xcopy /e /i /y /q "%ROOT%\docs" "%PREFIX%\docs" >nul

REM Build driver (resolves build\nurlc.exe + stdlib\runtime.o relative to itself).
copy /y "%ROOT%\nurl.bat" "%PREFIX%\nurl.bat" >nul

REM -- Bundled installer - this is what `nurl upgrade` runs ------
REM Shipping it means an in-place upgrade executes the script that came
REM WITH the toolchain you already trust, instead of downloading one and
REM piping it to a shell. Mirrors install-toolchain.sh.
if not exist "%PREFIX%\libexec" mkdir "%PREFIX%\libexec"
if exist "%ROOT%\tools\get-nurl.ps1" (
  copy /y "%ROOT%\tools\get-nurl.ps1" "%PREFIX%\libexec\get-nurl.ps1" >nul
) else (
  echo Note: tools\get-nurl.ps1 absent - "nurl upgrade" will not be available.
)

REM ── Bundled zig backend (optional but recommended) ─────────────
REM Mirrors install-toolchain.sh: point NURL_BUNDLE_ZIG at an extracted
REM zig dist (the dir with zig.exe + lib\) and it is staged at
REM %PREFIX%\zig\. The wasmbuilder package uses it for local wasm32-wasi
REM builds (zig carries wasi-libc + wasm-ld); without it, wasmbuilder's
REM first build downloads zig on demand instead.
set "ZIG_SRC=%NURL_BUNDLE_ZIG%"
if not defined ZIG_SRC set "ZIG_SRC=%ROOT%\vendor\zig"
if exist "%ZIG_SRC%\zig.exe" (
  echo Bundling zig backend from %ZIG_SRC%
  if exist "%PREFIX%\zig" rmdir /s /q "%PREFIX%\zig"
  xcopy /e /i /y /q "%ZIG_SRC%" "%PREFIX%\zig" >nul
) else (
  echo Note: no bundled zig ^(%ZIG_SRC%\zig.exe absent^) - wasm builds will fetch zig on first use.
)

REM ── PATH shims (RELOCATABLE) ──────────────────────────────────
REM Each shim resolves the prefix from its OWN location (%%~dp0..) at
REM runtime, so the extracted tree works wherever it lands. It defaults
REM NURL_STDLIB to the prefix so the compiler finds the shipped stdlib
REM from any directory. The nurlpkg shim also points NURL at the driver.
> "%PREFIX%\bin\nurl.bat" (
  echo @echo off
  echo for %%%%I in ^("%%~dp0.."^) do set "NURL_PREFIX=%%%%~fI"
  echo if not defined NURL_STDLIB set "NURL_STDLIB=%%NURL_PREFIX%%"
  echo call "%%NURL_PREFIX%%\nurl.bat" %%*
)
> "%PREFIX%\bin\nurlc.bat" (
  echo @echo off
  echo for %%%%I in ^("%%~dp0.."^) do set "NURL_PREFIX=%%%%~fI"
  echo if not defined NURL_STDLIB set "NURL_STDLIB=%%NURL_PREFIX%%"
  echo "%%NURL_PREFIX%%\build\nurlc.exe" %%*
)
> "%PREFIX%\bin\nurlpkg.bat" (
  echo @echo off
  echo for %%%%I in ^("%%~dp0.."^) do set "NURL_PREFIX=%%%%~fI"
  echo if not defined NURL_STDLIB set "NURL_STDLIB=%%NURL_PREFIX%%"
  echo if not defined NURL set "NURL=%%NURL_PREFIX%%\bin\nurl.bat"
  echo "%%NURL_PREFIX%%\build\nurlpkg.exe" %%*
)
if "%HAVE_NURLFMT%"=="1" (
  > "%PREFIX%\bin\nurlfmt.bat" (
    echo @echo off
    echo for %%%%I in ^("%%~dp0.."^) do set "NURL_PREFIX=%%%%~fI"
    echo if not defined NURL_STDLIB set "NURL_STDLIB=%%NURL_PREFIX%%"
    echo "%%NURL_PREFIX%%\build\nurlfmt.exe" %%*
  )
)

REM ── Sourceable session env (RELOCATABLE) ──────────────────────
> "%PREFIX%\env.bat" (
  echo @echo off
  echo for %%%%I in ^("%%~dp0"^) do set "NURL_HOME=%%%%~fI"
  echo set "NURL_STDLIB=%%NURL_HOME%%"
  echo set "PATH=%%NURL_HOME%%\bin;%%PATH%%"
)

echo Done.
echo.
if "%HAVE_NURLFMT%"=="1" (
  echo   installed:  nurl, nurlc, nurlpkg, nurlfmt  -^> %PREFIX%\bin
) else (
  echo   installed:  nurl, nurlc, nurlpkg  -^> %PREFIX%\bin
)
echo   stdlib:     %%NURL_STDLIB%%        -^> %PREFIX%\stdlib
echo   docs:                             -^> %PREFIX%\docs
echo.
echo Activate it in this shell:
echo     call "%PREFIX%\env.bat"
echo.
echo Make it permanent (adds the bin dir + NURL_STDLIB to your user env):
echo     setx NURL_STDLIB "%PREFIX%"
echo     setx PATH "%PREFIX%\bin;%%PATH%%"
echo.
echo Then, from anywhere:
echo     nurlpkg install nq
exit /b 0

:uninstall
if exist "%PREFIX%\bin"      rmdir /s /q "%PREFIX%\bin"
if exist "%PREFIX%\build"    rmdir /s /q "%PREFIX%\build"
if exist "%PREFIX%\stdlib"   rmdir /s /q "%PREFIX%\stdlib"
if exist "%PREFIX%\docs"     rmdir /s /q "%PREFIX%\docs"
if exist "%PREFIX%\zig"      rmdir /s /q "%PREFIX%\zig"
if exist "%PREFIX%\nurl.bat" del /q "%PREFIX%\nurl.bat"
if exist "%PREFIX%\env.bat"  del /q "%PREFIX%\env.bat"
echo Removed NURL toolchain from %PREFIX%
exit /b 0
