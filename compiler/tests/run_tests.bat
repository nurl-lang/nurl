@echo off
REM ============================================================
REM  run_tests.bat - for every .nu in this directory:
REM     1. compile with nurlc (to LLVM IR)
REM     2. if compile OK, link with clang + runtime.o
REM     3. if link OK, run the binary with a timeout and capture
REM        stdout+stderr + exit code
REM
REM  Output (since PURIFY.md Phase 5, 2026-05-23):
REM   - success.txt   only the tests whose outcome matched the
REM                   expectation. Compared to correct.txt as the
REM                   snapshot baseline.
REM   - failures.txt  only the tests whose outcome did not match,
REM                   with the exact compile / link command and
REM                   full captured stderr. Empty when everything
REM                   went well.
REM
REM  Exit code:
REM   - 0 when success.txt == correct.txt AND failures.txt is empty
REM   - 1 on baseline diff OR any unexpected failure
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

if not exist "%NURLC%" (
    echo ERROR: nurlc not found at %NURLC% 1>&2
    echo        Run: build.bat 1>&2
    exit /b 2
)
if not exist "%RUNTIME%" (
    echo ERROR: runtime.o not found at %RUNTIME% 1>&2
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

set "SUCCESS=%SCRIPT_DIR%\success.txt"
set "FAILURES=%SCRIPT_DIR%\failures.txt"
set "BASELINE=%SCRIPT_DIR%\correct.txt"
set "WORKDIR=%ROOT_DIR%\build\tests"

REM Cap captured output per-test so a runaway test can't balloon the baseline.
if not defined MAX_OUT_LINES set "MAX_OUT_LINES=200"
if not defined TIMEOUT set "TIMEOUT=10"

REM HTTP tests reach the public internet, so they're opt-in via NURL_HTTP_TESTS=1
REM (mirrors run_tests.sh). Default skips http_*.nu to keep the baseline stable.
if not defined NURL_HTTP_TESTS set "NURL_HTTP_TESTS=0"

REM net_* tests (except net_basic) need a permissive loopback environment;
REM opt-in via NURL_NET_TESTS=1 (mirrors run_tests.sh).
if not defined NURL_NET_TESTS set "NURL_NET_TESTS=0"

set "LINK_FLAGS=-O2 -lwinhttp"

type nul > "%SUCCESS%"
type nul > "%FAILURES%"
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

for /f "usebackq delims=" %%F in ("%FILELIST%") do call :run_one "%%F"
del "%FILELIST%" 2>nul

set "EXIT_STATUS=0"

if not exist "%BASELINE%" (
    copy /Y "%SUCCESS%" "%BASELINE%" >nul
    echo No baseline found - created correct.txt from current success.txt.
    echo Review it and commit if it reflects the expected state.
) else (
    fc /B "%SUCCESS%" "%BASELINE%" >nul 2>&1
    if errorlevel 1 (
        echo TESTS FAILED - success.txt differs from correct.txt:
        echo.
        fc "%BASELINE%" "%SUCCESS%"
        echo.
        set "EXIT_STATUS=1"
    )
)

REM Report failures.txt if non-empty.
for %%F in ("%FAILURES%") do set "FAIL_SIZE=%%~zF"
if defined FAIL_SIZE if !FAIL_SIZE! gtr 0 (
    echo.
    echo === failures recorded in compiler\tests\failures.txt ===
    type "%FAILURES%"
    set "EXIT_STATUS=1"
)

if "!EXIT_STATUS!"=="0" echo TESTS PASSED
exit /b !EXIT_STATUS!

REM ── run_one <file.nu> ───────────────────────────────────────────
REM Compile / link / run a single test and append the verdict to
REM success.txt or failures.txt. A subroutine (not a loop body) so
REM plain %var% expansion and goto work without paren-nesting issues.
:run_one
set "name=%~n1"
set "src=%SCRIPT_DIR%\%~1"
set "ll=%WORKDIR%\%name%.ll"
set "bin=%WORKDIR%\%name%.exe"
set "out=%WORKDIR%\%name%.out"
set "err=%WORKDIR%\%name%.err"
if exist "%ll%"  del "%ll%"  >nul 2>&1
if exist "%bin%" del "%bin%" >nul 2>&1
if exist "%out%" del "%out%" >nul 2>&1
if exist "%err%" del "%err%" >nul 2>&1

REM Skip helper modules (no main).
if "%name:~-4%"=="_mod"    exit /b 0
if "%name:~-7%"=="_helper" exit /b 0
if "%name:~-4%"=="_lib"    exit /b 0

REM Skip network-dependent HTTP tests unless explicitly enabled; the
REM pure parser/builder/router subset runs by default (mirrors
REM run_tests.sh http_runs_by_default).
set "SKIP=0"
if "%name:~0,5%"=="http_" if not "%NURL_HTTP_TESTS%"=="1" set "SKIP=1"
if "%name%"=="http_request_parser"  set "SKIP=0"
if "%name%"=="http_response_builder" set "SKIP=0"
if "%name%"=="http_router"     set "SKIP=0"
if "%name%"=="http_extras"     set "SKIP=0"
if "%name%"=="http_middleware" set "SKIP=0"
if "%name%"=="http_form"       set "SKIP=0"
if "%name%"=="http_multipart"  set "SKIP=0"
if "%name%"=="http_proxy"      set "SKIP=0"

REM net_* (except net_basic) opt-in via NURL_NET_TESTS=1.
if "%name:~0,4%"=="net_" if not "%name%"=="net_basic" if not "%NURL_NET_TESTS%"=="1" set "SKIP=1"
if "%SKIP%"=="1" exit /b 0

REM borrow_*, diag_* and should_fail_* expect COMPILE FAIL; borrow_strict_*
REM only fires under the stricter checker flag (mirrors run_tests.sh).
set "EXPECT_FAIL=0"
set "CFLAGS="
if "%name:~0,12%"=="should_fail_" set "EXPECT_FAIL=1"
if "%name:~0,7%"=="borrow_"       set "EXPECT_FAIL=1"
if "%name:~0,5%"=="diag_"         set "EXPECT_FAIL=1"
if "%name:~0,14%"=="borrow_strict_" set "CFLAGS=--strict-borrowck"

"%NURLC%" %CFLAGS% "%src%" > "%ll%" 2>"%err%"
set "CC_EC=%errorlevel%"

if "%EXPECT_FAIL%"=="1" goto :ro_expect_fail
if not "%CC_EC%"=="0" goto :ro_compile_fail

"%CLANG%" -O2 "%ll%" "%RUNTIME%" -lwinhttp -o "%bin%" 2>"%err%"
if not "%errorlevel%"=="0" goto :ro_link_fail

REM Run with cwd = WORKDIR and argv[0] = ".\name.exe" so argv-sensitive
REM tests produce the same output regardless of the absolute path
REM where the repo lives.
pushd "%WORKDIR%" >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $p = Start-Process -FilePath ('.\\' + '%name%' + '.exe') -RedirectStandardOutput '%out%.o' -RedirectStandardError '%out%.e' -PassThru -NoNewWindow -WorkingDirectory (Get-Location); if (-not $p.WaitForExit(%TIMEOUT% * 1000)) { try { $p.Kill() } catch {}; exit 124 } else { exit $p.ExitCode }"
set "EC=%errorlevel%"
if exist "%out%.o" (
    if exist "%out%.e" (
        copy /B "%out%.o"+"%out%.e" "%out%" >nul 2>&1
    ) else (
        copy /B "%out%.o" "%out%" >nul 2>&1
    )
) else (
    if exist "%out%.e" ( copy /B "%out%.e" "%out%" >nul 2>&1 ) else ( type nul > "%out%" )
)
del "%out%.o" "%out%.e" >nul 2>&1
popd >nul
>>"%SUCCESS%" echo === %name% ===
>>"%SUCCESS%" echo COMPILE OK
>>"%SUCCESS%" echo LINK OK
>>"%SUCCESS%" echo EXIT %EC%
>>"%SUCCESS%" echo OUTPUT
call :append_output_capped "%out%"
>>"%SUCCESS%" echo.
exit /b 0

:ro_expect_fail
if "%CC_EC%"=="0" goto :ro_unexpected_pass
>>"%SUCCESS%" echo === %name% ===
>>"%SUCCESS%" echo COMPILE FAIL
>>"%SUCCESS%" echo.
exit /b 0

:ro_unexpected_pass
>>"%FAILURES%" echo === %name% ===
>>"%FAILURES%" echo [1/2] compiler/tests/%name%.nu -^> build/tests/%name%.ll
>>"%FAILURES%" echo ^(expected COMPILE FAIL but compiler accepted the program^)
if exist "%err%" type "%err%" >> "%FAILURES%"
>>"%FAILURES%" echo.
exit /b 0

:ro_compile_fail
REM nurlc refuses FFI decls whose external lib wasn't found at build
REM time ("no build-time sentinel 'stdlib/runtime.<lib>'"). That's an
REM environment gap, not a regression — skip, like run_tests.sh skips
REM categories its environment can't run.
findstr /c:"no build-time sentinel" "%err%" >nul 2>&1 && exit /b 0
>>"%FAILURES%" echo === %name% ===
>>"%FAILURES%" echo [1/2] compiler/tests/%name%.nu -^> build/tests/%name%.ll
if exist "%err%" type "%err%" >> "%FAILURES%"
>>"%FAILURES%" echo.
exit /b 0

:ro_link_fail
>>"%FAILURES%" echo === %name% ===
>>"%FAILURES%" echo [1/2] compiler/tests/%name%.nu -^> build/tests/%name%.ll
>>"%FAILURES%" echo [2/2] build/tests/%name%.ll -^> build/tests/%name%.exe  ^(%LINK_FLAGS%^)
if exist "%err%" type "%err%" >> "%FAILURES%"
>>"%FAILURES%" echo.
exit /b 0

:append_output_capped
set "OF=%~1"
if not exist "%OF%" ( >>"%SUCCESS%" echo. & exit /b 0 )
for /f %%A in ('type "%OF%" ^| find /c /v ""') do set "LINES=%%A"
if !LINES! leq %MAX_OUT_LINES% (
    type "%OF%" >> "%SUCCESS%"
) else (
    powershell -NoProfile -Command "Get-Content -LiteralPath '%OF%' -TotalCount %MAX_OUT_LINES%" >> "%SUCCESS%"
    set /a "REST=!LINES! - %MAX_OUT_LINES%"
    >>"%SUCCESS%" echo [... !REST! more lines truncated ...]
)
exit /b 0
