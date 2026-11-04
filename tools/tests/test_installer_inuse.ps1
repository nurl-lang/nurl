# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  The Windows installer must replace a toolchain that is running.
#
#  `nurl upgrade` runs tools/get-nurl.ps1 from bin\nurl.exe, so the
#  installer always meets at least one file Windows will not delete.
#  Remove-ToolchainPath renames such files aside (<name>.old-<id>). It
#  used to name them by $_.FullName inside a catch block, where $_ is
#  the error record: the rename got a $null path and the upgrade died
#  with "Cannot bind argument to parameter 'Path' because it is null".
#
#  This loads the installer's own helper functions (by AST, so nothing
#  is downloaded) and runs them against a prefix whose bin\nurl.exe and
#  zig\zig.exe are live processes.
#
#    powershell -NoProfile -ExecutionPolicy Bypass -File tools\tests\test_installer_inuse.ps1
# ============================================================
$ErrorActionPreference = "Stop"

$installer = Join-Path $PSScriptRoot "..\get-nurl.ps1"
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $installer), [ref]$null, [ref]$null)
foreach ($name in @("Use-OwnModulePath", "New-StalePath", "Remove-ToolchainPath")) {
    $fn = $ast.Find({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq $name }, $true)
    if (-not $fn) { throw "get-nurl.ps1 defines no $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}

$fail = 0
function Check($cond, $what) {
    if ($cond) { Write-Host "ok: $what" }
    else { Write-Host "FAIL: $what"; $script:fail = 1 }
}

# -- Module path: run from pwsh 7 through cmd (as `nurl upgrade` is, and
#    as CI runs this file) the inherited PSModulePath names PowerShell 7's
#    modules first, and Get-FileHash does not load until they are gone.
$inherited = $env:PSModulePath
$fromPwsh = $PSVersionTable.PSEdition -ne "Core" -and
    (($inherited -split ';') | Where-Object { $_.TrimEnd('\') -match '\\PowerShell\\Modules$' })
Use-OwnModulePath
$after = $env:PSModulePath -split ';'
Check (-not ($after | Where-Object { $_.TrimEnd('\') -match '\\PowerShell\\Modules$' })) `
    "no PowerShell 7 module directory is left on PSModulePath"
Check ($after | Where-Object { $_ -match '\\WindowsPowerShell\\' }) `
    "Windows PowerShell's own module directories stay"
$hashOk = $true
try { $null = Get-FileHash -LiteralPath $installer -Algorithm SHA256 } catch { $hashOk = $false }
Check $hashOk "Get-FileHash loads$(if ($fromPwsh) { ' (started from pwsh 7)' } else { '' })"
if ($env:NURL_TEST_EXPECT_PWSH_PARENT -eq "1") {
    Check $fromPwsh "the test really ran with pwsh 7's module path inherited"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nurl-inuse-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$prefix = Join-Path $tmp "pre fix"
$procs = @()
try {
    foreach ($d in @("bin", "zig\lib")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $prefix $d) | Out-Null
    }
    # A running image can be renamed but not deleted - exactly the state
    # bin\nurl.exe is in during `nurl upgrade`.
    $ping = Join-Path $env:SystemRoot "System32\PING.EXE"
    $nurlExe = Join-Path $prefix "bin\nurl.exe"
    $zigExe = Join-Path $prefix "zig\zig.exe"
    Copy-Item $ping $nurlExe
    Copy-Item $ping $zigExe
    Set-Content -Path (Join-Path $prefix "bin\nurlc.bat") -Value "@echo off"
    Set-Content -Path (Join-Path $prefix "zig\lib\std.zig") -Value "// std"
    foreach ($exe in @($nurlExe, $zigExe)) {
        $procs += Start-Process -FilePath $exe -ArgumentList "-n", "60", "127.0.0.1" `
            -WindowStyle Hidden -PassThru
    }
    Start-Sleep -Milliseconds 500
    try { Remove-Item -LiteralPath $nurlExe -Force -ErrorAction Stop; $locked = $false }
    catch { $locked = $true }
    if (-not $locked) { throw "test setup: a running exe was deletable, nothing is exercised" }

    # A running file on its own (the bin\*.exe entries).
    Remove-ToolchainPath $nurlExe
    Check (-not (Test-Path -LiteralPath $nurlExe)) "a running bin\nurl.exe is moved out of the way"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $prefix "bin") -Filter "nurl.exe.old-*").Count -eq 1) `
        "it is kept as bin\nurl.exe.old-<id> for the next run to sweep"

    # A directory holding a running file (zig\, stdlib\, ...).
    Remove-ToolchainPath (Join-Path $prefix "zig")
    Check (-not (Test-Path -LiteralPath (Join-Path $prefix "zig"))) "a directory with a running exe in it is moved out of the way"
    Check (@(Get-ChildItem -LiteralPath $prefix -Directory -Filter "zig.old-*").Count -eq 1) `
        "it is kept as zig.old-<id> for the next run to sweep"

    # Nothing in use: plain delete, no stale copy.
    $bat = Join-Path $prefix "bin\nurlc.bat"
    Remove-ToolchainPath $bat
    Check (-not (Test-Path -LiteralPath $bat)) "an idle file is deleted"
    Check (@(Get-ChildItem -LiteralPath (Join-Path $prefix "bin") -Filter "nurlc.bat.old-*").Count -eq 0) `
        "an idle file leaves no stale copy"

    # A path that is not there is not an error.
    Remove-ToolchainPath (Join-Path $prefix "docs")
    Check $true "a missing path is a no-op"
}
finally {
    foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $p.WaitForExit() } catch { } }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
exit $fail
