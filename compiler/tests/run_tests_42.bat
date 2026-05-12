@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0..\.."
set "NURLC=%ROOT%\build\nurlc.exe"
set "TESTS=%ROOT%\compiler\tests"
set "BUILD=%ROOT%\build"

set PASS=0
set FAIL=0

echo ============================================
echo  4.2 Result-type and try-propagation tests
echo ============================================
echo.

REM ── Test 1 (t8): Result OK path ──────────────
echo [T8] Result OK path (should compile + output OK: 5)
"%NURLC%" "%TESTS%\t8_result_ok.nu" > "%BUILD%\t8.ll" 2>"%BUILD%\t8_err.txt"
if !errorlevel! neq 0 (
    echo   FAIL: compilation failed
    type "%BUILD%\t8_err.txt"
    set /a FAIL+=1
) else (
    clang "%BUILD%\t8.ll" "%ROOT%\stdlib\runtime.o" -lwinhttp -o "%BUILD%\t8.exe" >nul 2>&1
    "%BUILD%\t8.exe" > "%BUILD%\t8_out.txt" 2>&1
    findstr /c:"PASS" "%BUILD%\t8_out.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        findstr /c:"OK: 5" "%BUILD%\t8_out.txt" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   PASS
            set /a PASS+=1
        ) else (
            echo   FAIL: wrong output
            type "%BUILD%\t8_out.txt"
            set /a FAIL+=1
        )
    ) else (
        echo   FAIL: wrong output
        type "%BUILD%\t8_out.txt"
        set /a FAIL+=1
    )
)

REM ── Test 2 (t9): Result Err path ─────────────
echo [T9] Result Err path (should compile + output ERR: division by zero)
"%NURLC%" "%TESTS%\t9_result_err.nu" > "%BUILD%\t9.ll" 2>"%BUILD%\t9_err.txt"
if !errorlevel! neq 0 (
    echo   FAIL: compilation failed
    type "%BUILD%\t9_err.txt"
    set /a FAIL+=1
) else (
    clang "%BUILD%\t9.ll" "%ROOT%\stdlib\runtime.o" -lwinhttp -o "%BUILD%\t9.exe" >nul 2>&1
    "%BUILD%\t9.exe" > "%BUILD%\t9_out.txt" 2>&1
    findstr /c:"PASS" "%BUILD%\t9_out.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        findstr /c:"ERR: division by zero" "%BUILD%\t9_out.txt" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   PASS
            set /a PASS+=1
        ) else (
            echo   FAIL: wrong output
            type "%BUILD%\t9_out.txt"
            set /a FAIL+=1
        )
    ) else (
        echo   FAIL: wrong output
        type "%BUILD%\t9_out.txt"
        set /a FAIL+=1
    )
)

REM ── Test 3 (t10): Try chain OK ────────────────
echo [T10] Try chain OK (should compile + output OK: 10)
"%NURLC%" "%TESTS%\t10_try_ok.nu" > "%BUILD%\t10.ll" 2>"%BUILD%\t10_err.txt"
if !errorlevel! neq 0 (
    echo   FAIL: compilation failed
    type "%BUILD%\t10_err.txt"
    set /a FAIL+=1
) else (
    clang "%BUILD%\t10.ll" "%ROOT%\stdlib\runtime.o" -lwinhttp -o "%BUILD%\t10.exe" >nul 2>&1
    "%BUILD%\t10.exe" > "%BUILD%\t10_out.txt" 2>&1
    findstr /c:"PASS" "%BUILD%\t10_out.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        findstr /c:"OK: 10" "%BUILD%\t10_out.txt" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   PASS
            set /a PASS+=1
        ) else (
            echo   FAIL: wrong output
            type "%BUILD%\t10_out.txt"
            set /a FAIL+=1
        )
    ) else (
        echo   FAIL: wrong output
        type "%BUILD%\t10_out.txt"
        set /a FAIL+=1
    )
)

REM ── Test 4 (t11): Try propagates Err ──────────
echo [T11] Try propagates Err (should compile + output ERR: division by zero)
"%NURLC%" "%TESTS%\t11_try_propagate_err.nu" > "%BUILD%\t11.ll" 2>"%BUILD%\t11_err.txt"
if !errorlevel! neq 0 (
    echo   FAIL: compilation failed
    type "%BUILD%\t11_err.txt"
    set /a FAIL+=1
) else (
    clang "%BUILD%\t11.ll" "%ROOT%\stdlib\runtime.o" -lwinhttp -o "%BUILD%\t11.exe" >nul 2>&1
    "%BUILD%\t11.exe" > "%BUILD%\t11_out.txt" 2>&1
    findstr /c:"PASS" "%BUILD%\t11_out.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        findstr /c:"ERR: division by zero" "%BUILD%\t11_out.txt" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   PASS
            set /a PASS+=1
        ) else (
            echo   FAIL: wrong output
            type "%BUILD%\t11_out.txt"
            set /a FAIL+=1
        )
    ) else (
        echo   FAIL: wrong output
        type "%BUILD%\t11_out.txt"
        set /a FAIL+=1
    )
)

REM ── Test 5 (t12): Mid-chain error ─────────────
echo [T12] Mid-chain error (should compile + output ERR: division by zero)
"%NURLC%" "%TESTS%\t12_try_mid_chain.nu" > "%BUILD%\t12.ll" 2>"%BUILD%\t12_err.txt"
if !errorlevel! neq 0 (
    echo   FAIL: compilation failed
    type "%BUILD%\t12_err.txt"
    set /a FAIL+=1
) else (
    clang "%BUILD%\t12.ll" "%ROOT%\stdlib\runtime.o" -lwinhttp -o "%BUILD%\t12.exe" >nul 2>&1
    "%BUILD%\t12.exe" > "%BUILD%\t12_out.txt" 2>&1
    findstr /c:"PASS" "%BUILD%\t12_out.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        findstr /c:"ERR: division by zero" "%BUILD%\t12_out.txt" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   PASS
            set /a PASS+=1
        ) else (
            echo   FAIL: wrong output
            type "%BUILD%\t12_out.txt"
            set /a FAIL+=1
        )
    ) else (
        echo   FAIL: wrong output
        type "%BUILD%\t12_out.txt"
        set /a FAIL+=1
    )
)

REM ── Test 6 (t13): Enum error type ─────────────
echo [T13] Enum error type (should compile + output ERR: div by zero)
"%NURLC%" "%TESTS%\t13_result_enum_err.nu" > "%BUILD%\t13.ll" 2>"%BUILD%\t13_err.txt"
if !errorlevel! neq 0 (
    echo   FAIL: compilation failed
    type "%BUILD%\t13_err.txt"
    set /a FAIL+=1
) else (
    clang "%BUILD%\t13.ll" "%ROOT%\stdlib\runtime.o" -lwinhttp -o "%BUILD%\t13.exe" >nul 2>&1
    "%BUILD%\t13.exe" > "%BUILD%\t13_out.txt" 2>&1
    findstr /c:"PASS" "%BUILD%\t13_out.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        findstr /c:"ERR: div by zero" "%BUILD%\t13_out.txt" >nul 2>&1
        if !errorlevel! equ 0 (
            echo   PASS
            set /a PASS+=1
        ) else (
            echo   FAIL: wrong output
            type "%BUILD%\t13_out.txt"
            set /a FAIL+=1
        )
    ) else (
        echo   FAIL: wrong output
        type "%BUILD%\t13_out.txt"
        set /a FAIL+=1
    )
)

REM ── Test 7 (t14): \ on non-Result type ────────
echo [T14] try on non-Result type (should error: try operator)
"%NURLC%" "%TESTS%\t14_try_non_result.nu" >nul 2>"%BUILD%\t14_err.txt"
if !errorlevel! equ 0 (
    echo   FAIL: compiler accepted invalid code
    set /a FAIL+=1
) else (
    findstr /c:"try operator" "%BUILD%\t14_err.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   PASS
        set /a PASS+=1
    ) else (
        echo   FAIL: wrong error message
        type "%BUILD%\t14_err.txt"
        set /a FAIL+=1
    )
)

REM ── Test 8 (t15): Result type mismatch ────────
echo [T15] Result type mismatch (should error: try propagation type mismatch)
"%NURLC%" "%TESTS%\t15_result_type_mismatch.nu" >nul 2>"%BUILD%\t15_err.txt"
if !errorlevel! equ 0 (
    echo   FAIL: compiler accepted invalid code
    set /a FAIL+=1
) else (
    findstr /c:"try propagation type mismatch" "%BUILD%\t15_err.txt" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   PASS
        set /a PASS+=1
    ) else (
        echo   FAIL: wrong error message
        type "%BUILD%\t15_err.txt"
        set /a FAIL+=1
    )
)

echo.
echo ============================================
echo  Results: %PASS% PASS  /  %FAIL% FAIL  (of 8)
echo ============================================

if %FAIL% neq 0 exit /b 1
exit /b 0
