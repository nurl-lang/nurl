@echo off
REM Copyright (c) 2026 The NURL Project Developers
REM SPDX-License-Identifier: MIT OR Apache-2.0
REM Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
REM Clean build artifacts from both build\ directory and legacy locations

echo Cleaning NURL build artifacts...

REM Clean build directory
if exist build (
    echo   Cleaning build\ directory...
    del /Q build\* 2>nul
)

REM Clean legacy artifacts from root directory
echo   Cleaning legacy artifacts from root directory...
del /Q *.ll 2>nul
del /Q nurlc.exe 2>nul
del /Q nurlc_py* 2>nul
del /Q nurlc_self* 2>nul
del /Q *.tmp 2>nul

REM Clean Python cache
echo   Cleaning Python cache...
for /d /r . %%d in (__pycache__) do @if exist "%%d" rd /s /q "%%d" 2>nul
del /s /q *.pyc 2>nul

echo Clean complete!