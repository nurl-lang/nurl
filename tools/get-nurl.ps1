# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  get-nurl.ps1 - one-line installer for the NURL toolchain on Windows.
#
#  Downloads the matching release archive from GitHub Releases, verifies
#  its SHA-256, and unpacks the relocatable toolchain into $NURL_HOME
#  (default %USERPROFILE%\.nurl). Then add %NURL_HOME%\bin to PATH.
#
#  Usage (PowerShell):
#    irm https://nurl-lang.org/install.ps1 | iex
#    & ([scriptblock]::Create((irm https://nurl-lang.org/install.ps1))) -Version v0.1.0
#
#  Params:
#    -Version <tag>   release tag to install (default: latest)
#    -Prefix  <dir>   install prefix (default: %USERPROFILE%\.nurl)
# ============================================================
param(
    [string]$Version = $env:NURL_VERSION,
    [string]$Prefix  = $(if ($env:NURL_HOME) { $env:NURL_HOME } else { Join-Path $env:USERPROFILE ".nurl" })
)
$ErrorActionPreference = "Stop"
$repo = "nurl-lang/nurl"
$target = "windows-x86_64"

# ── Resolve version (latest release tag if unset) ──────────────────────
if (-not $Version) {
    Write-Host "resolving latest release..."
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
    $Version = $rel.tag_name
    if (-not $Version) { throw "could not determine the latest release tag; pass -Version vX.Y.Z." }
}

$archive = "nurl-$Version-$target.zip"
$base = "https://github.com/$repo/releases/download/$Version"
$tmp = Join-Path $env:TEMP ("nurl-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Write-Host "downloading $archive ($Version)..."
    $zip = Join-Path $tmp $archive
    Invoke-WebRequest "$base/$archive" -OutFile $zip

    # ── Verify checksum (best-effort) ──────────────────────────────────
    try {
        $sumFile = "$zip.sha256"
        Invoke-WebRequest "$base/$archive.sha256" -OutFile $sumFile
        $want = ((Get-Content $sumFile) -split '\s+')[0].ToLower()
        $got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        if ($want -ne $got) { throw "checksum mismatch (expected $want, got $got)." }
        Write-Host "checksum OK"
    } catch {
        Write-Host "warning: checksum verification skipped ($($_.Exception.Message))"
    }

    # ── Unpack (archive has a top-level nurl\ dir) ─────────────────────
    Write-Host "installing to $Prefix..."
    if (Test-Path $Prefix) { Remove-Item -Recurse -Force $Prefix }
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $unzipTmp = Join-Path $tmp "x"
    Expand-Archive -Path $zip -DestinationPath $unzipTmp -Force
    Copy-Item -Recurse -Force (Join-Path $unzipTmp "nurl\*") $Prefix

    if (-not (Test-Path (Join-Path $Prefix "bin\nurl.bat"))) {
        throw "install looks incomplete: $Prefix\bin\nurl.bat missing."
    }

    Write-Host ""
    Write-Host "NURL $Version installed -> $Prefix"
    Write-Host ""
    Write-Host "Add it to this session:"
    Write-Host "    `$env:Path = `"$Prefix\bin;`$env:Path`""
    Write-Host "Make it permanent:"
    Write-Host "    setx PATH `"$Prefix\bin;%PATH%`""
    Write-Host "    setx NURL_STDLIB `"$Prefix`""
    Write-Host ""
    Write-Host "Then:  nurlc --version   ·   nurlpkg install argz-demo"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
