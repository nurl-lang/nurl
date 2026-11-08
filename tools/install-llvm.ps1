# tools/install-llvm.ps1 — the clang/LLVM this repository builds with, on Windows.
#
# The Windows twin of tools/install-llvm.sh. The VERSION is read from that
# script, so the repository pins LLVM in one place; the digest below is
# the Windows installer's own (GitHub's published sha256 for the release
# asset) and changes with it. Chocolatey's `llvm` package trails LLVM's
# releases, and an unpinned `choco install llvm` installs whatever it has
# that day, so CI installs LLVM's own MSI instead.
#
#   pwsh tools/install-llvm.ps1
#
# It installs to C:\Program Files\LLVM, where build.bat and nurl.bat look,
# and fails unless clang.exe there then reports the pinned version.
$ErrorActionPreference = "Stop"

$LlvmMsiSha256 = "288ab326377157a9e02e6fb9724914cc2b55963882d493a405f31dc66e837c12"

$sh = Get-Content (Join-Path $PSScriptRoot "install-llvm.sh") -Raw
if ($sh -notmatch '(?m)^LLVM_VERSION=([0-9.]+)\s*$') { throw "no LLVM_VERSION= line in tools/install-llvm.sh" }
$v = $Matches[1]

$msi = Join-Path ([System.IO.Path]::GetTempPath()) "LLVM-$v-win64.msi"
$url = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$v/LLVM-$v-win64.msi"
Write-Host "install-llvm.ps1: $url"
Invoke-WebRequest $url -OutFile $msi -MaximumRetryCount 8 -RetryIntervalSec 5
$got = (Get-FileHash $msi -Algorithm SHA256).Hash.ToLowerInvariant()
if ($got -ne $LlvmMsiSha256) { throw "LLVM-$v-win64.msi sha256 is $got, expected $LlvmMsiSha256" }

$p = Start-Process msiexec.exe -ArgumentList @("/i", "`"$msi`"", "/qn", "/norestart") -Wait -PassThru
if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "msiexec exited $($p.ExitCode)" }
Remove-Item $msi -ErrorAction SilentlyContinue

$clang = "C:\Program Files\LLVM\bin\clang.exe"
$out = (& $clang --version | Select-Object -First 1)
if ($out -notmatch "clang version $([regex]::Escape($v))\b") { throw "$clang reports '$out', expected $v" }
Write-Host "install-llvm.ps1: $out"
