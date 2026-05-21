@echo off
REM ============================================================
REM  run_tests.bat - for every .nu in this directory:
REM     1. compile with nurlc (to LLVM IR)
REM     2. if compile OK, link with build\nurl-build.exe
REM     3. if link OK, run the binary with a timeout and capture
REM        stdout+stderr + exit code
REM  A single snapshot file testresults.txt records the full
REM  outcome for each test (status, exit code, captured output).
REM
REM  Compared to correct.txt as baseline:
REM   - missing baseline -> testresults.txt is copied over as the
REM     initial baseline
REM   - identical         -> print "TESTS PASSED"
REM   - different         -> print diff and exit 1
REM
REM  Windows counterpart of run_tests.sh - same logic, same
REM  output file format.
REM ============================================================
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
pushd "%SCRIPT_DIR%\..\.." >nul
set "ROOT_DIR=%CD%"
popd >nul

set "NURLC=%ROOT_DIR%\build\nurlc.exe"
set "RUNTIME=%ROOT_DIR%\stdlib\runtime.o"
set "NURLBUILD=%ROOT_DIR%\build\nurl-build.exe"

if not exist "%NURLC%" (
    echo ERROR: nurlc not found at %NURLC% 1>&2
    echo        Run: build.bat 1>&2
    exit /b 2
)
if not exist "%RUNTIME%" (
    echo ERROR: runtime.o not found at %RUNTIME% 1>&2
    exit /b 2
)
if not exist "%NURLBUILD%" (
    if defined NURL_ZIG (
        set "ZIG=%NURL_ZIG%"
    ) else (
        set "ZIG=zig"
    )
    where "%ZIG%" >nul 2>&1
    if errorlevel 1 (
        echo ERROR: nurl-build helper not found at %NURLBUILD% 1>&2
        echo        Run: zig build nurl-build 1>&2
        exit /b 2
    )
    pushd "%ROOT_DIR%" >nul
    "%ZIG%" build nurl-build >nul 2>&1
    set "RC=%ERRORLEVEL%"
    popd >nul
    if not "%RC%"=="0" (
        echo ERROR: zig build nurl-build failed 1>&2
        exit /b 2
    )
)
if not exist "%NURLBUILD%" (
    echo ERROR: nurl-build helper not found at %NURLBUILD% 1>&2
    exit /b 2
)

if not defined CLANG set "CLANG=clang"
where "%CLANG%" >nul 2>&1
if errorlevel 1 (
    set "CLANG="
    if exist "C:\Program Files\LLVM\bin\clang.exe" set "CLANG=C:\Program Files\LLVM\bin\clang.exe"
    if not defined CLANG if exist "C:\Program Files (x86)\LLVM\bin\clang.exe" set "CLANG=C:\Program Files (x86)\LLVM\bin\clang.exe"
    if not defined CLANG (
        echo ERROR: clang not found 1>&2
        exit /b 2
    )
)

set "RESULTS=%SCRIPT_DIR%\testresults.txt"
set "BASELINE=%SCRIPT_DIR%\correct.txt"
set "WORKDIR=%ROOT_DIR%\build\tests"

REM Cap captured output per-test so a runaway test can't balloon the baseline.
if not defined MAX_OUT_LINES set "MAX_OUT_LINES=200"
if not defined TIMEOUT set "TIMEOUT=10"

REM HTTP tests reach the public internet, so they're opt-in via NURL_HTTP_TESTS=1
REM (mirrors run_tests.sh). Default skips http_*.nu to keep the baseline stable.
if not defined NURL_HTTP_TESTS set "NURL_HTTP_TESTS=0"

type nul > "%RESULTS%"
if not exist "%WORKDIR%" mkdir "%WORKDIR%"

REM Gather *.nu files and sort them (LC_ALL=C equivalent via default ASCII sort).
set "FILELIST=%TEMP%\nurl_tests_%RANDOM%%RANDOM%.lst"
dir /b /a-d "%SCRIPT_DIR%\*.nu" 2>nul | sort > "%FILELIST%"
for /f %%A in ('type "%FILELIST%" ^| find /c /v ""') do set "NTESTS=%%A"
if "%NTESTS%"=="0" (
    echo ERROR: no .nu files found in %SCRIPT_DIR% 1>&2
    del "%FILELIST%" 2>nul
    exit /b 2
)

for /f "usebackq delims=" %%F in ("%FILELIST%") do (
    set "src=%SCRIPT_DIR%\%%F"
    set "name=%%~nF"
    set "ll=%WORKDIR%\!name!.ll"
    set "bin=%WORKDIR%\!name!.exe"
    set "out=%WORKDIR%\!name!.out"
    if exist "!ll!"  del "!ll!"  >nul 2>&1
    if exist "!bin!" del "!bin!" >nul 2>&1
    if exist "!out!" del "!out!" >nul 2>&1

    REM Skip network-dependent HTTP tests unless explicitly enabled. Setting
    REM SKIP=1 short-circuits every block below so the test produces no entry
    REM in testresults.txt at all, matching run_tests.sh's behaviour.
    set "SKIP=0"
    echo !name! | findstr /b /c:"http_" >nul
    if !errorlevel! equ 0 if not "%NURL_HTTP_TESTS%"=="1" set "SKIP=1"
    REM http_request_parser + http_response_builder + http_router are pure
    REM parser/builder/router (no socket), exempt from gate. mcp_http is
    REM also pure (offline handler exercise); not http_-prefixed but the
    REM SKIP gate above already let it through — no extra carve-out
    REM needed.
    if "!name!"=="http_request_parser" set "SKIP=0"
    if "!name!"=="http_response_builder" set "SKIP=0"
    if "!name!"=="http_router" set "SKIP=0"
    if "!name!"=="http_extras" set "SKIP=0"
    if "!name!"=="http_middleware" set "SKIP=0"
    if "!name!"=="http_form" set "SKIP=0"
    if "!name!"=="http_multipart" set "SKIP=0"
    if "!name!"=="http_proxy" set "SKIP=0"

    if "!SKIP!"=="0" (
        >>"%RESULTS%" echo === !name! ===

        "%NURLC%" "!src!" > "!ll!" 2>nul
        if errorlevel 1 (
            >>"%RESULTS%" echo COMPILE FAIL
            >>"%RESULTS%" echo.
        ) else (
            >>"%RESULTS%" echo COMPILE OK
            "%NURLBUILD%" --driver "%CLANG%" --opt -O2 --runtime "%RUNTIME%" --no-lto "%ROOT_DIR%" "!ll!" "!bin!" 2>nul
            if errorlevel 1 (
                >>"%RESULTS%" echo LINK FAIL
                >>"%RESULTS%" echo.
            ) else (
                >>"%RESULTS%" echo LINK OK
                REM Run with cwd = WORKDIR and argv[0] = ".\name.exe" so argv-sensitive
                REM tests produce the same output regardless of the absolute path
                REM where the repo lives. Use PowerShell to enforce a hard timeout,
                REM merging stdout + stderr into !out!.
                pushd "%WORKDIR%" >nul
                powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $p = Start-Process -FilePath ('.\\' + '!name!' + '.exe') -RedirectStandardOutput '!out!.o' -RedirectStandardError '!out!.e' -PassThru -NoNewWindow -WorkingDirectory (Get-Location); if (-not $p.WaitForExit(%TIMEOUT% * 1000)) { try { $p.Kill() } catch {}; exit 124 } else { exit $p.ExitCode }"
                set "EC=!errorlevel!"
                if exist "!out!.o" (
                    if exist "!out!.e" (
                        copy /B "!out!.o"+"!out!.e" "!out!" >nul 2>&1
                    ) else (
                        copy /B "!out!.o" "!out!" >nul 2>&1
                    )
                ) else (
                    if exist "!out!.e" ( copy /B "!out!.e" "!out!" >nul 2>&1 ) else ( type nul > "!out!" )
                )
                del "!out!.o" "!out!.e" >nul 2>&1
                popd >nul
                >>"%RESULTS%" echo EXIT !EC!
                >>"%RESULTS%" echo OUTPUT
                call :append_output_capped "!out!"
                >>"%RESULTS%" echo.
            )
        )
    )
)
del "%FILELIST%" 2>nul

if not exist "%BASELINE%" (
    copy /Y "%RESULTS%" "%BASELINE%" >nul
    echo No baseline found - created correct.txt from current results.
    echo Review it and commit if it reflects the expected state.
    exit /b 0
)

fc /B "%RESULTS%" "%BASELINE%" >nul 2>&1
if not errorlevel 1 (
    echo TESTS PASSED
    exit /b 0
)

echo TESTS FAILED - testresults.txt differs from correct.txt:
echo.
fc "%BASELINE%" "%RESULTS%"
exit /b 1

:append_output_capped
set "OF=%~1"
if not exist "%OF%" ( >>"%RESULTS%" echo. & exit /b 0 )
for /f %%A in ('type "%OF%" ^| find /c /v ""') do set "LINES=%%A"
if !LINES! leq %MAX_OUT_LINES% (
    type "%OF%" >> "%RESULTS%"
) else (
    powershell -NoProfile -Command "Get-Content -LiteralPath '%OF%' -TotalCount %MAX_OUT_LINES%" >> "%RESULTS%"
    set /a "REST=!LINES! - %MAX_OUT_LINES%"
    >>"%RESULTS%" echo [... !REST! more lines truncated ...]
)
exit /b 0
