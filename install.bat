@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM ============================================================
REM  install.bat - single-command install of NURL's developer
REM                experience on Windows.
REM
REM  Stages (each skippable; idempotent on re-run):
REM    1. Bootstrap the compiler  (build.bat if build\nurlc.exe missing)
REM    2. Build the LSP server    (tools\nurl-lsp\build.bat)
REM    3. Copy build\nurl-lsp.exe into %%USERPROFILE%%\.local\bin so VS Code
REM       and Windsurf find it on PATH without any setting tweaks.
REM    4. Package + install the VS Code extension via the `code` CLI
REM       (or `windsurf` / `cursor`). Skipped when none is on PATH.
REM
REM  Flags:
REM    --no-vscode   Don't try to install the VS Code extension even
REM                  if `code` is on PATH.
REM    --no-path     Don't touch %%USERPROFILE%%\.local\bin - leave the
REM                  binary where build.bat put it (build\nurl-lsp.exe).
REM    --force       Rebuild even if the artefacts already exist.
REM    --uninstall   Remove %%USERPROFILE%%\.local\bin\nurl-lsp.exe + the
REM                  installed extension; leave the build tree alone.
REM    -h | --help   Show this help.
REM
REM  Stderr/stdout: clearly-labelled stage banners; failures print the
REM  underlying tool's output and exit 1.
REM
REM  Windows counterpart of install.sh - same stages, same exit codes,
REM  same idempotency guarantees. Symlinks are replaced by file copies
REM  because creating a symlink on Windows requires either Developer
REM  Mode or SeCreateSymbolicLinkPrivilege, neither of which is typical.
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%" >nul

set "NO_VSCODE=0"
set "NO_PATH=0"
set "FORCE=0"
set "UNINSTALL=0"

REM ── Parse flags ──────────────────────────────────────────────
:parse_flags
if "%~1"=="" goto :done_parse
if /i "%~1"=="--no-vscode" ( set "NO_VSCODE=1" & shift & goto :parse_flags )
if /i "%~1"=="--no-path"   ( set "NO_PATH=1"   & shift & goto :parse_flags )
if /i "%~1"=="--force"     ( set "FORCE=1"     & shift & goto :parse_flags )
if /i "%~1"=="--uninstall" ( set "UNINSTALL=1" & shift & goto :parse_flags )
if /i "%~1"=="-h"          goto :usage
if /i "%~1"=="--help"      goto :usage
echo unknown arg: %~1 (try --help) 1>&2
popd >nul
exit /b 2
:done_parse

REM ── Detect editor CLI ────────────────────────────────────────
REM `where` resolves the basename via PATH+PATHEXT, returning one path
REM per line. We capture the first hit and the basename separately:
REM   - EDITOR_CLI is the bare name used in user-facing messages.
REM   - EDITOR_BIN is the full path to the `.cmd` shim, used at call
REM     sites. `call "code"` (quoted basename) trips cmd's internal
REM     `%~dp0` resolution inside the launcher script and ends up
REM     looking for Code.exe under the install.bat's own directory.
REM     Pre-resolving the absolute path fixes that.
set "EDITOR_CLI="
set "EDITOR_BIN="
for %%c in (code cursor windsurf) do (
    if not defined EDITOR_CLI (
        for /f "delims=" %%P in ('where %%c 2^>nul') do (
            if not defined EDITOR_BIN if exist "%%P" (
                set "EDITOR_CLI=%%c"
                set "EDITOR_BIN=%%P"
            )
        )
    )
)

REM ── Uninstall path ───────────────────────────────────────────
if "%UNINSTALL%"=="1" goto :do_uninstall

REM ── 1/4 Bootstrap compiler ───────────────────────────────────
call :banner "1/4 Compiler bootstrap"
set "DO_BUILD=0"
if "%FORCE%"=="1" set "DO_BUILD=1"
if not exist "%SCRIPT_DIR%\build\nurlc.exe" set "DO_BUILD=1"
if "%DO_BUILD%"=="1" (
    echo   zig build bootstrap ^(this can take a minute^)...
    set "BUILD_LOG=%TEMP%\nurl_install_build_%RANDOM%%RANDOM%.log"
    zig build bootstrap > "!BUILD_LOG!" 2>&1
    if not exist "%SCRIPT_DIR%\build\nurlc.exe" (
        powershell -NoProfile -Command "Get-Content -LiteralPath '!BUILD_LOG!' -Tail 30"
        call :die "zig build bootstrap failed (full log: !BUILD_LOG!)"
        popd >nul
        exit /b 1
    )
    if exist "!BUILD_LOG!" del "!BUILD_LOG!" >nul 2>&1
    call :ok "build\nurlc.exe ready"
) else (
    call :ok "build\nurlc.exe already present (use --force to rebuild)"
)

REM ── 2/4 Build LSP ────────────────────────────────────────────
call :banner "2/4 Language Server"
set "DO_LSP=0"
if "%FORCE%"=="1" set "DO_LSP=1"
if not exist "%SCRIPT_DIR%\build\nurl-lsp.exe" set "DO_LSP=1"
if "%DO_LSP%"=="1" (
    set "LSP_LOG=%TEMP%\nurl_install_lsp_%RANDOM%%RANDOM%.log"
    zig build nurl-lsp > "!LSP_LOG!" 2>&1
    if errorlevel 1 (
        powershell -NoProfile -Command "Get-Content -LiteralPath '!LSP_LOG!' -Tail 30"
        call :die "zig build nurl-lsp failed (full log: !LSP_LOG!)"
        popd >nul
        exit /b 1
    )
    if exist "!LSP_LOG!" del "!LSP_LOG!" >nul 2>&1
    call :ok "build\nurl-lsp.exe built"
) else (
    call :ok "build\nurl-lsp.exe already present"
)

REM ── 3/4 PATH install ─────────────────────────────────────────
if "%NO_PATH%"=="1" (
    call :banner "3/4 PATH install (skipped -- --no-path)"
    goto :stage_vscode
)
call :banner "3/4 PATH install"
set "BINDIR=%USERPROFILE%\.local\bin"
if not exist "%BINDIR%" mkdir "%BINDIR%"
set "SRC=%SCRIPT_DIR%\build\nurl-lsp.exe"
set "DST=%BINDIR%\nurl-lsp.exe"
REM Windows can't ergonomically symlink without elevation; copy instead.
REM The behavioural contract (callers find nurl-lsp on PATH and get the
REM most recently built binary) is preserved because we always copy.
copy /Y "%SRC%" "%DST%" >nul
if errorlevel 1 (
    call :die "failed to copy %SRC% to %DST%"
    popd >nul
    exit /b 1
)
REM Plain `to` instead of `->` / `<-`: shell redirection metacharacters
REM survive intact through the :ok helper's call/echo pipeline and would
REM either trigger a redirect or swallow the line entirely.
call :ok "copied %SRC% to %DST%"
echo %PATH% | findstr /I /C:"%BINDIR%" >nul
if errorlevel 1 (
    call :warn "%BINDIR% is NOT on PATH -- add it via:"
    echo     setx PATH "%%PATH%%;%BINDIR%"
    echo     ^(then open a new terminal for the change to take effect^)
) else (
    call :ok "%BINDIR% on PATH"
)

:stage_vscode
REM ── 4/4 VS Code extension ────────────────────────────────────
if "%NO_VSCODE%"=="1" (
    call :banner "4/4 VS Code extension (skipped -- --no-vscode)"
    goto :done
)
if not defined EDITOR_CLI (
    call :banner "4/4 VS Code extension (skipped -- no editor CLI)"
    call :warn "neither 'code', 'cursor', nor 'windsurf' is on PATH"
    call :warn "install the .vsix manually: tooling\vscode-nurl\nurl-^<ver^>.vsix"
    goto :done
)
call :banner "4/4 VS Code extension via '%EDITOR_CLI%'"
where npx >nul 2>&1
if errorlevel 1 (
    call :warn "npx not on PATH -- install Node.js to build the .vsix"
    call :warn "(syntax highlighting + LSP still work via Manual install)"
    goto :done
)
REM Extract version from tooling\vscode-nurl\package.json. We pull a tiny
REM PowerShell snippet here because cmd has no native JSON parser, and
REM findstr-based regex would be brittle when the field order or quoting
REM in package.json shifts during publishing.
for /f "usebackq delims=" %%V in (`powershell -NoProfile -Command "(Get-Content -Raw 'tooling\vscode-nurl\package.json' | ConvertFrom-Json).version"`) do set "VER=%%V"
if not defined VER (
    call :die "failed to read version from tooling\vscode-nurl\package.json"
    popd >nul
    exit /b 1
)
set "VSIX=tooling\vscode-nurl\nurl-%VER%.vsix"
set "DO_PKG=0"
if "%FORCE%"=="1" set "DO_PKG=1"
if not exist "%VSIX%" set "DO_PKG=1"
if "%DO_PKG%"=="1" (
    echo   packaging %VSIX% ...
    pushd "tooling\vscode-nurl" >nul
    if not exist node_modules (
        call npm install --silent >nul 2>&1
    )
    set "VSCE_LOG=%TEMP%\nurl_install_vsce_%RANDOM%%RANDOM%.log"
    call npx --yes vsce package -o "nurl-%VER%.vsix" > "!VSCE_LOG!" 2>&1
    if errorlevel 1 (
        powershell -NoProfile -Command "Get-Content -LiteralPath '!VSCE_LOG!' -Tail 30"
        popd >nul
        call :die "vsce package failed"
        popd >nul
        exit /b 1
    )
    del "!VSCE_LOG!" >nul 2>&1
    popd >nul
)
call :ok "%VSIX% ready"

REM Check whether the extension at this exact version is already installed.
REM `code --list-extensions --show-versions` prints lines like
REM `nurl-lang.nurl@0.4.4`; a literal match short-circuits the install.
set "INSTALLED="
REM `for /f` with a piped command and a quoted path-with-spaces in the
REM backtick block is fragile — cmd routes the pipe through Electron's
REM own arg parser when it can't decide where the quoted command ends.
REM Route through a tempfile instead.
set "EXT_LIST=%TEMP%\nurl_install_extlist_%RANDOM%%RANDOM%.txt"
REM `call` is mandatory when invoking another .cmd from a batch file —
REM without it, control transfers to code.cmd and never returns, so
REM the rest of install.bat (the version compare + Done banner) is
REM silently skipped.
call "%EDITOR_BIN%" --list-extensions --show-versions > "%EXT_LIST%" 2>nul
for /f "usebackq delims=" %%L in (`findstr /B /C:"nurl-lang.nurl@" "%EXT_LIST%"`) do set "INSTALLED=%%L"
del "%EXT_LIST%" >nul 2>&1
if "%INSTALLED%"=="nurl-lang.nurl@%VER%" if "%FORCE%"=="0" (
    call :ok "%EDITOR_CLI% already has nurl-lang.nurl@%VER%"
    goto :done
)
set "EXT_LOG=%TEMP%\nurl_install_ext_%RANDOM%%RANDOM%.log"
call "%EDITOR_BIN%" --install-extension "%VSIX%" --force > "!EXT_LOG!" 2>&1
if errorlevel 1 (
    powershell -NoProfile -Command "Get-Content -LiteralPath '!EXT_LOG!' -Tail 30"
    call :die "%EDITOR_CLI% --install-extension failed"
    popd >nul
    exit /b 1
)
del "!EXT_LOG!" >nul 2>&1
call :ok "installed nurl-lang.nurl@%VER% into %EDITOR_CLI%"

:done
echo.
call :banner "Done"
echo   Open a .nu file in your editor; the LSP will start automatically.
echo   Smoke test: open examples\fizzbuzz.nu and hover over a function name.
echo   Re-run any time -- this script is idempotent.
echo   Uninstall: install.bat --uninstall
popd >nul
exit /b 0

REM ── Uninstall subroutine ─────────────────────────────────────
:do_uninstall
call :banner "Uninstall"
set "BIN=%USERPROFILE%\.local\bin\nurl-lsp.exe"
if exist "%BIN%" (
    del /q "%BIN%" >nul 2>&1
    call :ok "removed %BIN%"
) else (
    call :warn "%BIN% not present"
)
if not defined EDITOR_BIN goto :uninstall_done
REM Tempfile is materialised at top scope (not inside an `if (...)` block)
REM so the immediate `findstr` errorlevel propagates correctly. The same
REM pattern is used for the install-side detection above.
set "UN_LIST=%TEMP%\nurl_uninstall_extlist_%RANDOM%%RANDOM%.txt"
REM `--show-versions` so each line is `pub.name@x.y.z` — the `@` suffix
REM gives findstr a hard anchor and avoids `/X` (which silently fails
REM on dotted strings even with /C:).
call "%EDITOR_BIN%" --list-extensions --show-versions > "%UN_LIST%" 2>nul
findstr /B /C:"nurl-lang.nurl@" "%UN_LIST%" >nul
if errorlevel 1 (
    call :warn "VS Code extension nurl-lang.nurl not installed"
) else (
    call "%EDITOR_BIN%" --uninstall-extension nurl-lang.nurl >nul 2>&1
    call :ok "uninstalled VS Code extension nurl-lang.nurl"
)
if exist "%UN_LIST%" del "%UN_LIST%" >nul 2>&1
:uninstall_done
echo.
call :ok "Uninstall complete. The build\ tree is untouched."
popd >nul
exit /b 0

REM ── Helper subroutines ───────────────────────────────────────
:banner
echo.
echo == %~1 ==
exit /b 0

:ok
echo   [OK] %~1
exit /b 0

:warn
REM Avoid `[!]` here: `setlocal enabledelayedexpansion` makes cmd treat
REM `!...!` as a variable reference, which silently swallows the prefix
REM together with the next exclamation in the same line.
echo   [W]  %~1
exit /b 0

:die
echo ERROR: %~1 1>&2
exit /b 1

:usage
echo Usage: install.bat [--no-vscode] [--no-path] [--force] [--uninstall] [-h^|--help]
echo.
echo   --no-vscode   Don't try to install the VS Code extension.
echo   --no-path     Don't touch %%USERPROFILE%%\.local\bin.
echo   --force       Rebuild even if artefacts already exist.
echo   --uninstall   Remove the LSP binary + extension; leave build\ alone.
echo   -h, --help    Show this help.
popd >nul
exit /b 0
