@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM ============================================================
REM  version.bat - print the NURL toolchain version. Windows
REM  counterpart of tools/version.sh; SAME resolution order so
REM  `nurlc --version` matches across platforms.
REM
REM  Resolution order:
REM    1. `git describe --tags --always --dirty` (exact tag on a
REM       release, else <tag>-<n>-g<sha>[-dirty] on a dev checkout).
REM    2. newest released CHANGELOG.md section (source tarball, no git).
REM    3. v0.0.0.
REM ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT=%SCRIPT_DIR%\.."

set "VER="
for /f "delims=" %%v in ('git -C "%ROOT%" describe --tags --always --dirty 2^>nul') do set "VER=%%v"
if not defined VER (
    REM No git (source tarball): fall back to the newest CHANGELOG.md entry,
    REM e.g. `## [0.9.16] - ...` -> v0.9.16. tokens=2 delims=[] picks the
    REM bracketed version; `if not defined` keeps only the first (newest).
    for /f "tokens=2 delims=[]" %%a in ('findstr /r /c:"^## \[[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\]" "%ROOT%\CHANGELOG.md" 2^>nul') do (
        if not defined VER set "VER=v%%a"
    )
)
if not defined VER set "VER=v0.0.0"
echo %VER%
endlocal
