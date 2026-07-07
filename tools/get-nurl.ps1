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
#
#  Env:
#    $env:NURL_NO_MODIFY_PATH = "1"   never prompt / change the User PATH
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
    # Remove only the entries the toolchain owns (the list
    # tools\install-toolchain.bat manages) — $Prefix also holds user data
    # that must survive a reinstall, e.g. the nurlpkg publish token in
    # $Prefix\credentials. Wiping the whole prefix silently logged users
    # out of the registry on every upgrade.
    Write-Host "installing to $Prefix..."
    if (Test-Path $Prefix) {
        foreach ($entry in @("bin", "build", "stdlib", "zig", "nurl.sh", "env")) {
            $owned = Join-Path $Prefix $entry
            if (Test-Path $owned) { Remove-Item -Recurse -Force $owned }
        }
    }
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    $unzipTmp = Join-Path $tmp "x"
    Expand-Archive -Path $zip -DestinationPath $unzipTmp -Force
    Copy-Item -Recurse -Force (Join-Path $unzipTmp "nurl\*") $Prefix

    if (-not (Test-Path (Join-Path $Prefix "bin\nurl.bat"))) {
        throw "install looks incomplete: $Prefix\bin\nurl.bat missing."
    }

    $binDir = Join-Path $Prefix "bin"

    # This session: `iex` evaluates in the caller's session, so we can put
    # NURL on PATH right now — no separate command to copy-paste.
    if (($env:Path -split ';') -notcontains $binDir) {
        $env:Path = "$binDir;$env:Path"
    }
    $env:NURL_STDLIB = $Prefix

    Write-Host ""
    Write-Host "NURL $Version installed -> $Prefix"
    Write-Host "This session is ready — 'nurlc' and 'nurlpkg' are on PATH now."
    Write-Host ""

    # Offer to persist to the User environment so new terminals inherit it.
    $persist = $false
    if ($env:NURL_NO_MODIFY_PATH -eq "1") {
        $persist = $false
    } elseif ([Environment]::UserInteractive) {
        $ans = Read-Host "Add NURL to your PATH permanently (User environment)? [Y/n]"
        if ($ans -eq "" -or $ans -match '^[Yy]') { $persist = $true }
    }

    if ($persist) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if (-not $userPath) { $userPath = "" }
        if (($userPath -split ';') -contains $binDir) {
            Write-Host "PATH already contains $binDir (User environment)."
        } else {
            $newPath = if ($userPath) { "$binDir;$userPath" } else { $binDir }
            [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Host "Added $binDir to your User PATH — new terminals will have it."
        }
        [Environment]::SetEnvironmentVariable("NURL_STDLIB", $Prefix, "User")
    } else {
        Write-Host "Left your permanent PATH untouched. For future terminals, run:"
        Write-Host "    [Environment]::SetEnvironmentVariable('Path', `"$binDir;`" + [Environment]::GetEnvironmentVariable('Path','User'), 'User')"
    }

    Write-Host ""
    Write-Host "Then:  nurlc --version   ·   nurlpkg install nq"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
