<#
.SYNOPSIS
compare/run_bench.ps1 — reproducible CSV benchmark harness.

.DESCRIPTION
Runs .\nurl_analysis.exe and .\.venv\Scripts\python.exe polars_analysis.py
N times each, parses their stage timings, reports min/median per
stage, and appends one block to compare\HISTORY.md.

.EXAMPLE
.\run_bench.ps1                    # default 5
.\run_bench.ps1 -N 10              # run 10 times
.\run_bench.ps1 -NoHistory         # skip HISTORY.md append
.\run_bench.ps1 -Label "phase1"
#>

param (
    [int]$N = 5,
    [switch]$NoHistory,
    [string]$Label = ""
)

$ErrorActionPreference = "Stop"

# Aseta työhakemisto skriptin sijaintiin
$ScriptDir = $PSScriptRoot
Set-Location $ScriptDir

$AppendHistory = -not $NoHistory

$Py = "$ScriptDir\.venv\Scripts\python.exe"
$NurlBin = "$ScriptDir\nurl_analysis_arena.exe"
$Data = "$ScriptDir\test_data.csv"

# Tarkistetaan vaaditut tiedostot
if (-not (Test-Path $NurlBin)) { Write-Warning "missing $NurlBin — build nurl_analysis"; exit 1 }
if (-not (Test-Path $Py))      { Write-Warning "missing $Py — create venv and pip install polars"; exit 1 }
if (-not (Test-Path $Data))    { Write-Warning "missing $Data — run: $Py generate_data.py"; exit 1 }

$DataSha = (Get-FileHash $Data -Algorithm SHA256).Hash.ToLower()
$DataBytes = (Get-Item $Data).Length

# ── Helpers ──────────────────────────────────────────────────────────

function Get-Median($Array) {
    if ($Array.Count -eq 0) { return 0 }
    $Sorted = $Array | Sort-Object { [int]$_ }
    $Count = $Sorted.Count
    if ($Count % 2 -eq 1) {
        return $Sorted[[math]::Floor($Count / 2)]
    } else {
        return [math]::Round(($Sorted[$Count / 2 - 1] + $Sorted[$Count / 2]) / 2)
    }
}

function Get-Min($Array) {
    if ($Array.Count -eq 0) { return 0 }
    return ($Array | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum)
}

function Extract-Time($OutputLines, $Pattern) {
    foreach ($line in $OutputLines) {
        if ($line -match "$Pattern.*?(\d+)\s*ms") {
            return [int]$matches[1]
        }
    }
    return 0
}

# ── Run Benchmark ────────────────────────────────────────────────────

$NurlLoad = @(); $NurlFilt = @(); $NurlSort = @(); $NurlWrite = @(); $NurlTotal = @()
$PolLoad  = @(); $PolFilt  = @(); $PolSort  = @(); $PolWrite  = @(); $PolTotal  = @()

Write-Host "Running NURL ${N}x ..."
for ($i = 1; $i -le $N; $i++) {
    $out = & $NurlBin 2>$null
    $load  = Extract-Time $out "^Loaded"
    $filt  = Extract-Time $out "^Filtered"
    $sort  = Extract-Time $out "^Sorted"
    $write = Extract-Time $out "^Top-10"
    $total = Extract-Time $out "^Total:"

    $NurlLoad += $load; $NurlFilt += $filt; $NurlSort += $sort; $NurlWrite += $write; $NurlTotal += $total
    Write-Host "  run ${i}: load=${load}ms filter=${filt}ms sort=${sort}ms write=${write}ms total=${total}ms"
}

Write-Host "Running Polars ${N}x ..."
for ($i = 1; $i -le $N; $i++) {
    $out = & $Py polars_analysis.py 2>$null
    $load  = Extract-Time $out "^Loaded"
    $filt  = Extract-Time $out "^Filtered"
    $sort  = Extract-Time $out "^Sorted"
    $write = Extract-Time $out "^Top-10"
    $total = Extract-Time $out "^Total:"

    $PolLoad += $load; $PolFilt += $filt; $PolSort += $sort; $PolWrite += $write; $PolTotal += $total
    Write-Host "  run ${i}: load=${load}ms filter=${filt}ms sort=${sort}ms write=${write}ms total=${total}ms"
}

function Write-StatBlock($Name, $Array) {
    $mn = Get-Min $Array
    $md = Get-Median $Array
    $formattedName = $Name.PadRight(7)
    $fmtMn = $mn.ToString().PadLeft(5)
    $fmtMd = $md.ToString().PadLeft(5)
    Write-Host "$formattedName min=${fmtMn}ms  median=${fmtMd}ms"
}

Write-Host "`n── NURL ──────────────────────────────────────"
Write-StatBlock "load"   $NurlLoad
Write-StatBlock "filter" $NurlFilt
Write-StatBlock "sort"   $NurlSort
Write-StatBlock "write"  $NurlWrite
Write-StatBlock "total"  $NurlTotal

Write-Host "`n── Polars ────────────────────────────────────"
Write-StatBlock "load"   $PolLoad
Write-StatBlock "filter" $PolFilt
Write-StatBlock "sort"   $PolSort
Write-StatBlock "write"  $PolWrite
Write-StatBlock "total"  $PolTotal

# ── HISTORY.md append ────────────────────────────────────────────────

if ($AppendHistory) {
    $History = "$ScriptDir\HISTORY.md"
    $Date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ssZ")
    
    $GitDir = Split-Path -Parent $ScriptDir
    $Sha = "no-git"
    $Dirty = ""
    try {
        $Sha = (git -C $GitDir rev-parse --short HEAD 2>$null) | Out-String
        $Sha = $Sha.Trim()
        if ([string]::IsNullOrWhiteSpace($Sha)) { $Sha = "no-git" }
        
        git -C $GitDir diff --quiet 2>$null
        if ($LASTEXITCODE -ne 0 -and $Sha -ne "no-git") { $Dirty = "+dirty" }
    } catch {}

    $Cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $Os  = (Get-CimInstance Win32_OperatingSystem).Caption

    $Title = "## ${Date} — ${Sha}${Dirty}"
    if ($Label) { $Title += " — $Label" }

    $OutputBlock = @(
        "",
        $Title,
        "- CPU: $Cpu",
        "- OS: $Os",
        "- Fixture: test_data.csv (1 M rows × 8 cols, ${DataBytes} B, sha256=$($DataSha.Substring(0,16))…)",
        "- Runs: ${N} per implementation",
        "",
        "| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |",
        "|--------|---------:|---------:|-----------:|-----------:|------------------:|"
    )

    $Stages = @("load", "filter", "sort", "write", "total")
    foreach ($stage in $Stages) {
        switch ($stage) {
            "load"   { $na = $NurlLoad;  $pa = $PolLoad }
            "filter" { $na = $NurlFilt;  $pa = $PolFilt }
            "sort"   { $na = $NurlSort;  $pa = $PolSort }
            "write"  { $na = $NurlWrite; $pa = $PolWrite }
            "total"  { $na = $NurlTotal; $pa = $PolTotal }
        }
        $nm  = Get-Min $na
        $nme = Get-Median $na
        $pm  = Get-Min $pa
        $pme = Get-Median $pa
        
        $ratio = "—"
        if ($pme -gt 0) {
            $ratio = "{0:N1}x" -f ($nme / $pme)
            # Korvataan pilkku pisteellä varmuuden vuoksi, jos lokaali on suomi
            $ratio = $ratio -replace ',', '.'
        }
        
        $line = "| {0,-6} | {1,8} | {2,8} | {3,10} | {4,10} | {5,17} |" -f $stage, $nm, $nme, $pm, $pme, $ratio
        $OutputBlock += $line
    }

    $OutputBlock | Add-Content $History -Encoding UTF8
    Write-Host "`nAppended block to $History"
}