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
#    $env:NURL_INSTALL_INSECURE = "1" (or -Insecure) install even without a
#                                     verifiable checksum. OFF by default: a
#                                     missing checksum file ABORTS rather than
#                                     silently trusting unverified bytes.
# ============================================================
param(
    [string]$Version = $env:NURL_VERSION,
    [string]$Prefix  = $(if ($env:NURL_HOME) { $env:NURL_HOME } else { Join-Path $env:USERPROFILE ".nurl" }),
    [switch]$Insecure
)
if ($env:NURL_INSTALL_INSECURE -eq "1") { $Insecure = $true }
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

    # ── Verify checksum (fail-CLOSED unless -Insecure) ─────────────────
    # A checksum MISMATCH always aborts. Only the *inability* to fetch the
    # checksum file is what -Insecure downgrades to a warning. (Same-release
    # checksum defends against corruption, not a compromised release.)
    $sumFile = "$zip.sha256"
    $haveSum = $false
    try { Invoke-WebRequest "$base/$archive.sha256" -OutFile $sumFile; $haveSum = $true } catch { }
    if ($haveSum) {
        $want = ((Get-Content $sumFile) -split '\s+')[0].ToLower()
        $got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        if (-not $want) {
            if ($Insecure) { Write-Host "warning: empty checksum file — continuing (-Insecure)." }
            else { throw "the published checksum file is empty/malformed. Refusing; use -Insecure to override." }
        } elseif ($want -ne $got) {
            throw "checksum mismatch (expected $want, got $got) — refusing to install."
        } else {
            Write-Host "checksum OK"
        }
    } elseif ($Insecure) {
        Write-Host "warning: no checksum file for $Version — continuing (-Insecure)."
    } else {
        throw "no checksum file published for $Version ($archive.sha256). Refusing to install unverified bytes; use -Insecure to override."
    }

    # ── Signature (defense-in-depth beyond the same-release checksum) ──
    # If minisign is on PATH, verify the detached signature against the pinned
    # release key, fail-closed. If it isn't, we don't force an install of it —
    # checksum + HTTPS stay the root of trust (nurl's pure-NURL verifier covers
    # the package layer, where nurl is present).
    $minisignPub = "RWQT5WWtjTnEyaYAG5X4HKCRtb7rFT5psjJVGB5Q9kVQBI71F5jfPWUf"
    if (Get-Command minisign -ErrorAction SilentlyContinue) {
        $sig = "$zip.minisig"
        $haveSig = $false
        try { Invoke-WebRequest "$base/$archive.minisig" -OutFile $sig; $haveSig = $true } catch { }
        if ($haveSig) {
            & minisign -Vm $zip -P $minisignPub | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "signature verification FAILED — refusing to install." }
            Write-Host "signature OK"
        } elseif ($Insecure) {
            Write-Host "warning: no signature for $Version — continuing (-Insecure)."
        } else {
            throw "no signature (.minisig) published for $Version, and minisign is available to check it. Use -Insecure to override."
        }
    } else {
        Write-Host "note: minisign not installed — skipping signature check (checksum + HTTPS enforced)."
    }

    # ── Unpack (archive has a top-level nurl\ dir) ─────────────────────
    # Guard the wipe: never delete the user profile root or a directory that
    # isn't ours. Only clear an empty dir or a prior NURL install.
    $userRoot = $env:USERPROFILE.TrimEnd('\', '/')
    $pfxNorm  = "$Prefix".TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($pfxNorm) -or $pfxNorm -eq $userRoot) {
        throw "refusing to install into '$Prefix' — pick a dedicated directory (e.g. `$env:USERPROFILE\.nurl)."
    }
    Write-Host "installing to $Prefix..."
    if (Test-Path $Prefix) {
        $isNurl  = (Test-Path (Join-Path $Prefix "bin\nurl.bat")) -or (Test-Path (Join-Path $Prefix "bin\nurlc.exe"))
        $isEmpty = -not (Get-ChildItem -Force $Prefix -ErrorAction SilentlyContinue)
        if ($isNurl -or $isEmpty) { Remove-Item -Recurse -Force $Prefix }
        else { throw "'$Prefix' exists, is not empty, and is not a NURL install — refusing to overwrite it. Remove it yourself or set -Prefix to a fresh path." }
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
