#!/usr/bin/env pwsh
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  bench/bench.ps1 — the Windows benchmark runner. Faithful port
#  of bench/bench.sh: same corpus, same manifest, same protocol,
#  same two artefacts.
#
#  Every benchmark in bench/manifest.tsv is implemented five times —
#  NURL, C, Rust, Node, Python — and every implementation prints one
#  line. This script compiles what needs compiling, gates the row on all
#  five printing the *same* line, then times them and writes two
#  artefacts:
#
#    bench/results/latest-windows.json   machine-readable, schema 1 —
#                                        the same shape the landing
#                                        page's table generator reads
#    bench/RESULTS-WINDOWS.md            the same run rendered for
#                                        humans, with the compile-time
#                                        and correctness tables
#
#  Usage:
#      pwsh bench\bench.ps1                    # full suite, write both files
#      pwsh bench\bench.ps1 -Quick             # 1 rep/cell, for a smoke test
#      pwsh bench\bench.ps1 -Bench lcg,sieve
#      pwsh bench\bench.ps1 -Reps 9 -BudgetMs 20000
#      pwsh bench\bench.ps1 -Stdout            # print the report, touch nothing
#
#  Requires build\nurlc.exe + stdlib\runtime.o (build.bat), clang, rustc,
#  node and python. A missing toolchain is a hard error: a table with a
#  hole in it is worse than no table, because the hole is invisible once
#  the numbers are copied out.
#
#  ── Deliberate deviations from bench.sh, and why ────────────────
#
#  * SEPARATE OUTPUT FILES. bench.sh writes results/latest.json and
#    RESULTS.md, and the landing page's table is generated from the
#    former at publish time. Those are the *Linux CI* numbers. A local
#    Windows run must not overwrite them, or a careless commit ships
#    Windows timings as the project's published table — so this script
#    defaults to `-windows` variants. Pass -Json/-Md to override.
#
#  * NO -flto ON THE NURL LINK. bench.sh links NURL with
#    `clang -O2 -flto` because build.sh compiles stdlib/runtime.o to
#    LLVM bitcode. build.bat does NOT (see compiler/tests/run_tests.ps1,
#    which links the same way for the same reason), so runtime.o here is
#    a real object file and cross-module inlining into it is not
#    available. This is the link line a real `nurl.bat` build uses, byte
#    for byte, which is the property that matters — but it does mean the
#    NURL column is not directly comparable to a Linux run's.
#
#  * NO -lm / -lpthread, YES -lwinhttp. The MSVC CRT folds libm in, has
#    no separate pthread, and every NURL binary links the whole of
#    runtime.o — including its WinHTTP bridge. Same set as nurl.bat.
#    Feature libs build.bat detected (vcpkg zlib/zstd) come from
#    stdlib\runtime.winlibs, parsed exactly as run_tests.ps1 parses it.
#
#  * OUTPUT COMPARISON NORMALISES LINE ENDINGS. C's and Python's stdio
#    are in text mode on Windows and emit CRLF; the NURL runtime and
#    Node emit LF. Comparing raw bytes would fail all fifteen rows for a
#    reason that has nothing to do with the benchmark.
#
#  * PYTHON IS RESOLVED TO A REAL INTERPRETER PATH. `python3` usually
#    does not exist on Windows and `python` is often the App Execution
#    Alias stub. This script resolves through `py -3` to sys.executable
#    and times THAT, so the py-launcher's own dispatch cost does not
#    land in the Python column's floor.
#
#  Exit code: 0 iff every row passed the correctness gate, 1 otherwise.
# ============================================================
[CmdletBinding()]
param(
    # Time only these benchmarks (manifest names), instead of the whole roster.
    [string[]]$Bench,
    # Timed runs per cell, at most.
    [int]$Reps = 5,
    # Per-cell time budget in ms; a slow cell gets fewer reps.
    [int]$BudgetMs = 8000,
    # Per-run wall-clock cap, seconds.
    [int]$TimeoutS = 300,
    # Timed compiles per compiled language (median of).
    [int]$CompileReps = 3,
    [string]$Json,
    [string]$Md,
    # Print the Markdown report to stdout and write nothing.
    [switch]$Stdout,
    # 1 rep/cell, 1 compile/cell — a smoke test of the harness itself.
    [switch]$Quick
)
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$BenchDir  = Join-Path $Root 'bench'
$BuildDir  = Join-Path $BenchDir '_build'
$Manifest  = Join-Path $BenchDir 'manifest.tsv'

# ── settings ─────────────────────────────────────────────────────
$MaxReps = $Reps
$Opt     = '-O2'
if ($Quick) { $MaxReps = 1; $BudgetMs = 1; $CompileReps = 1 }
if (-not $Json) { $Json = Join-Path $BenchDir 'results\latest-windows.json' }
if (-not $Md)   { $Md   = Join-Path $BenchDir 'RESULTS-WINDOWS.md' }

# nurlc resolves `$ "stdlib/..."` imports relative to its working
# directory, so every compile and every run happens from $Root.
Set-Location $Root
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# ── toolchain detection ──────────────────────────────────────────
$Nurlc   = Join-Path $Root 'build\nurlc.exe'
$Runtime = Join-Path $Root 'stdlib\runtime.o'

# Resolve a command to an absolute executable path: PATH first, then the
# extra directories a Windows install might hide it in. Returns $null when
# nothing runnable was found.
function Resolve-Exe([string]$name, [string[]]$candidates = @()) {
    $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in $candidates) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
    return $null
}

# `python` on PATH is very often the Microsoft Store App Execution Alias:
# a 0-byte reparse point that prints an ad and exits non-zero. Only accept
# an interpreter that actually reports its own executable.
function Test-Python([string]$exe) {
    if (-not $exe) { return $null }
    try {
        $out = & $exe -c 'import sys; sys.stdout.write(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path -LiteralPath $out)) {
            return (Resolve-Path -LiteralPath $out).Path
        }
    } catch {}
    return $null
}
function Resolve-Python {
    if ($env:NURL_BENCH_PYTHON) {
        $r = Test-Python $env:NURL_BENCH_PYTHON
        if ($r) { return $r }
    }
    foreach ($n in 'python3', 'python') {
        $r = Test-Python (Resolve-Exe $n)
        if ($r) { return $r }
    }
    # The py launcher knows about every registered install; ask it for the
    # real interpreter path and time that directly, not the launcher.
    $py = Resolve-Exe 'py' @('C:\Windows\py.exe')
    if ($py) {
        try {
            $out = & $py -3 -c 'import sys; sys.stdout.write(sys.executable)' 2>$null
            if ($LASTEXITCODE -eq 0 -and $out -and (Test-Path -LiteralPath $out)) {
                return (Resolve-Path -LiteralPath $out).Path
            }
        } catch {}
    }
    return $null
}

$Clang  = Resolve-Exe ($env:CLANG ? $env:CLANG : 'clang') @(
              $env:CLANG,
              "$env:ProgramFiles\LLVM\bin\clang.exe",
              "${env:ProgramFiles(x86)}\LLVM\bin\clang.exe")
$Rustc  = Resolve-Exe 'rustc' @("$env:USERPROFILE\.cargo\bin\rustc.exe")
$Node   = Resolve-Exe 'node'  @("$env:ProgramFiles\nodejs\node.exe")
$Python = Resolve-Python

function First-Line([string]$s) {
    if (-not $s) { return '' }
    return (($s -replace "`r`n", "`n") -split "`n")[0].Trim()
}
# First line of `<exe> --version`, or $null when the thing cannot actually
# run. Existing on disk is not enough: `rustc.exe` in ~\.cargo\bin is a
# rustup SHIM, and a fresh `winget install Rustlang.Rustup` leaves it with
# no default toolchain — it resolves fine, then fails every compile. Caught
# here it is one line of diagnosis; caught later it is fifteen MISMATCH rows.
function Get-ToolVersion([string]$exe) {
    if (-not $exe) { return $null }
    try {
        $v = First-Line (& $exe --version 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $v) { return $v }
    } catch {}
    return $null
}

$ClangVersion  = Get-ToolVersion $Clang
$RustcVersion  = Get-ToolVersion $Rustc
$NodeVersion   = Get-ToolVersion $Node
$PythonVersion = Get-ToolVersion $Python

$missing = @()
if (-not (Test-Path -LiteralPath $Nurlc) -or -not (Test-Path -LiteralPath $Runtime)) {
    $missing += 'nurlc + stdlib\runtime.o (run build.bat)'
}
if     (-not $Clang)        { $missing += 'clang (install LLVM, or set CLANG=<path>)' }
elseif (-not $ClangVersion) { $missing += "clang at $Clang does not run" }
if     (-not $Rustc)        { $missing += 'rustc (install Rust: winget install Rustlang.Rustup)' }
elseif (-not $RustcVersion) { $missing += "rustc at $Rustc does not run (a rustup shim with no toolchain? run: rustup default stable)" }
if     (-not $Node)         { $missing += 'node' }
elseif (-not $NodeVersion)  { $missing += "node at $Node does not run" }
if     (-not $Python)       { $missing += 'python (set NURL_BENCH_PYTHON=<path> to override)' }
if ($missing.Count -gt 0) {
    Write-Host "bench.ps1: missing toolchain: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

# Feature libs build.bat detected (vcpkg zlib/zstd → stdlib\runtime.winlibs),
# so a NURL benchmark importing stdlib\ext\compress.nu links the way
# nurl.bat links it. Parsed into clean argv tokens — -L<dir> with quotes
# stripped (ArgumentList re-quotes if it has spaces) and -l<name> — exactly
# as compiler/tests/run_tests.ps1 does. This is the Windows counterpart of
# bench.sh's pkg-config EXTRA_LIBS block.
$WinLibs = @()
$winFile = Join-Path $Root 'stdlib\runtime.winlibs'
if (Test-Path -LiteralPath $winFile) {
    $winRaw = [System.IO.File]::ReadAllText($winFile)
    foreach ($m in [regex]::Matches($winRaw, '-L"([^"]*)"|-L(\S+)|-l(\S+)')) {
        if     ($m.Groups[1].Success) { $WinLibs += ('-L' + $m.Groups[1].Value) }
        elseif ($m.Groups[2].Success) { $WinLibs += ('-L' + $m.Groups[2].Value) }
        else                          { $WinLibs += ('-l' + $m.Groups[3].Value) }
    }
}
# Every NURL binary links the whole of runtime.o, including its WinHTTP
# bridge; the socket/bcrypt/advapi32 imports arrive on their own via the
# `#pragma comment(lib, ...)` directives in runtime_ffi.c under clang's
# MSVC target. Same set, same reason, as run_tests.ps1.
$NurlLinkLibs = @('-lwinhttp') + $WinLibs

$NurlVersion = Get-ToolVersion $Nurlc
if (-not $NurlVersion) {
    $NurlVersion = First-Line (& git -C $Root describe --tags --always --dirty 2>$null | Out-String)
}

# `uname -srm` has no Windows equivalent; assemble the same three facts.
$Arch       = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { 'AMD64' }
$HostKernel = "Windows $([System.Environment]::OSVersion.Version) $Arch"
$HostCpu    = $Arch
$HostCores  = [Environment]::ProcessorCount
$HostMemKb  = 0
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    if ($cpu.Name) { $HostCpu = $cpu.Name.Trim() }
    if ($cpu.NumberOfLogicalProcessors) { $HostCores = [int]$cpu.NumberOfLogicalProcessors }
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.TotalPhysicalMemory) { $HostMemKb = [int64]($cs.TotalPhysicalMemory / 1024) }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    if ($os.Caption) { $HostKernel = "$($os.Caption.Trim()) $($os.Version) $Arch" }
} catch {}
$HostLabel = if ($env:BENCH_HOST_LABEL) { $env:BENCH_HOST_LABEL } else { "Windows $Arch" }
$Commit    = First-Line (& git -C $Root rev-parse HEAD 2>$null | Out-String)
if (-not $Commit) { $Commit = 'unknown' }
$RunUrl    = if ($env:BENCH_RUN_URL) { $env:BENCH_RUN_URL } else { '' }

# ── timing helpers ───────────────────────────────────────────────
# One wall-clock reading in milliseconds, three decimals, measured with
# Stopwatch (QueryPerformanceCounter) around exactly the child process —
# no shell fork, no `timeout` wrapper, unlike the bash version which has
# to subtract its own overhead from $EPOCHREALTIME readings.
#
# stdout/stderr are redirected and read asynchronously: a benchmark that
# writes more than the pipe buffer would otherwise deadlock. Pass
# -StdoutFile to keep stdout instead of discarding it — nurlc writes its
# LLVM IR there, so the compile stage has to keep it while still being
# timed, and the write to disk is part of what bench.sh measures too.
#
# Returns 'TIMEOUT' when the cap is hit and 'FAIL' on a non-zero exit.
function Measure-Proc {
    param(
        [string]$Exe,
        [string[]]$Arguments = @(),
        [string]$StdoutFile,
        [switch]$PassThru        # also return the captured stdout
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    foreach ($a in $Arguments) { [void]$psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory       = $Root
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    # Windows auto-flags exes whose name contains "install"/"setup"/etc. as
    # requiring UAC elevation (installer-detection heuristic), which makes
    # Process.Start throw. RunAsInvoker suppresses it — same guard as
    # run_tests.ps1, cheap insurance for a future benchmark name.
    $psi.Environment['__COMPAT_LAYER'] = 'RunAsInvoker'

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try { $proc = [System.Diagnostics.Process]::Start($psi) }
    catch { return @{ Ms = 'FAIL'; Out = '' } }
    $o = $proc.StandardOutput.ReadToEndAsync()
    $e = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutS * 1000)) {
        try { $proc.Kill($true) } catch {}
        try { $proc.WaitForExit() } catch {}
        return @{ Ms = 'TIMEOUT'; Out = '' }
    }
    # STOP THE CLOCK HERE, on process exit — before draining the readers and
    # before touching the disk. WaitForExit(ms) returning true means the child
    # is gone; the argless overload below additionally waits for the async
    # readers, and the StdoutFile write is this script's bookkeeping, not the
    # child's cost. bench.sh has the child write to its own redirected fd and
    # measures only the process, so this is where the two agree.
    $sw.Stop()
    $ms = $sw.Elapsed.TotalMilliseconds
    $proc.WaitForExit()
    $code = $proc.ExitCode
    $out  = $o.Result
    [void]$e.Result
    if ($StdoutFile) { [System.IO.File]::WriteAllText($StdoutFile, $out, $Utf8NoBom) }
    if ($code -ne 0) { return @{ Ms = 'FAIL'; Out = $out } }
    $r = @{ Ms = ('{0:F3}' -f $ms); Out = '' }
    if ($PassThru -or $StdoutFile) { $r.Out = $out }
    return $r
}

function Time-Ms([string]$Exe, [string[]]$Arguments = @(), [string]$StdoutFile) {
    return (Measure-Proc -Exe $Exe -Arguments $Arguments -StdoutFile $StdoutFile).Ms
}

function Median([string[]]$values) {
    foreach ($v in $values) {
        if ($v -eq 'FAIL')    { return 'FAIL' }
        if ($v -eq 'TIMEOUT') { return 'TIMEOUT' }
    }
    if ($values.Count -eq 0) { return 'FAIL' }
    $n = @($values | ForEach-Object { [double]$_ } | Sort-Object)
    $c = $n.Count
    $m = if ($c % 2) { $n[[int](($c - 1) / 2)] } else { ($n[$c / 2 - 1] + $n[$c / 2]) / 2 }
    return ('{0:F3}' -f $m)
}

# Time a cell adaptively: one run first, then as many more as fit in
# BudgetMs, capped at MaxReps. A 6 ms cell gets the full 5 runs for 30 ms;
# a 25-second Python cell gets one, because a second run buys noise
# reduction the reader cannot use and costs another 25 seconds.
# Returns @{ Ms = <median or FAIL/TIMEOUT>; Reps = <n> }.
function Time-Cell([string]$Exe, [string[]]$Arguments = @()) {
    $first = Time-Ms $Exe $Arguments
    if ($first -eq 'FAIL' -or $first -eq 'TIMEOUT') { return @{ Ms = $first; Reps = 1 } }
    $runs = @($first)
    $f = [double]$first
    $n = if ($f -gt 0) { [int][Math]::Floor($BudgetMs / $f) } else { $MaxReps }
    if ($n -lt 1)        { $n = 1 }
    if ($n -gt $MaxReps) { $n = $MaxReps }
    while ($runs.Count -lt $n) {
        $r = Time-Ms $Exe $Arguments
        if ($r -eq 'FAIL' -or $r -eq 'TIMEOUT') { return @{ Ms = $r; Reps = $runs.Count } }
        $runs += $r
    }
    return @{ Ms = (Median $runs); Reps = $runs.Count }
}

# ── compile helpers ──────────────────────────────────────────────
# <src.nu> <outbase> → @{ Frontend = <ms>; Total = <ms> }, or FAIL in both.
function Compile-Nurl([string]$src, [string]$outbase) {
    $ll  = "$outbase.ll"
    $bin = "$outbase.nurl.exe"
    $fe = @(); $tot = @()
    for ($r = 0; $r -lt $CompileReps; $r++) {
        $f = Time-Ms $Nurlc @($src) -StdoutFile $ll
        if ($f -eq 'FAIL' -or $f -eq 'TIMEOUT') { return @{ Frontend = 'FAIL'; Total = 'FAIL' } }
        $l = Time-Ms $Clang (@($Opt, $ll, $Runtime) + $NurlLinkLibs + @('-o', $bin))
        if ($l -eq 'FAIL' -or $l -eq 'TIMEOUT') { return @{ Frontend = 'FAIL'; Total = 'FAIL' } }
        $fe  += $f
        $tot += ('{0:F3}' -f ([double]$f + [double]$l))
    }
    return @{ Frontend = (Median $fe); Total = (Median $tot) }
}

# `-lm` is deliberately absent: no benchmark includes <math.h> and the
# MSVC CRT folds libm in anyway, so naming it only makes lld-link hunt
# for a nonexistent m.lib.
function Compile-C([string]$src, [string]$outbase) {
    $bin = "$outbase.c.exe"
    $out = @()
    for ($r = 0; $r -lt $CompileReps; $r++) {
        $t = Time-Ms $Clang @($Opt, $src, '-o', $bin)
        if ($t -eq 'FAIL' -or $t -eq 'TIMEOUT') { return 'FAIL' }
        $out += $t
    }
    return (Median $out)
}

function Compile-Rust([string]$src, [string]$outbase) {
    $bin = "$outbase.rs.exe"
    $out = @()
    for ($r = 0; $r -lt $CompileReps; $r++) {
        $t = Time-Ms $Rustc @('-C', 'opt-level=2', $src, '-o', $bin)
        if ($t -eq 'FAIL' -or $t -eq 'TIMEOUT') { return 'FAIL' }
        $out += $t
    }
    return (Median $out)
}

# ── roster ───────────────────────────────────────────────────────
# `pwsh bench\bench.ps1 -Bench lcg,sieve` is -File invocation, and -File
# hands every argument over as a literal string — so the comma list arrives
# as ONE element, not three, and every name silently fails to match. Split
# it here so the documented spelling works from pwsh, cmd and a PowerShell
# prompt alike; `-Bench lcg,sieve` dot-sourced still binds as a real array
# and splitting it is a no-op.
if ($Bench) {
    $Bench = @($Bench | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
}

$names = @(); $blurbs = @(); $shapes = @()
foreach ($line in [System.IO.File]::ReadAllLines($Manifest)) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    $cols = $line -split "`t"
    if ($cols.Count -lt 3) { continue }
    $n = $cols[0].Trim()
    if (-not $n) { continue }
    if ($Bench -and ($Bench -notcontains $n)) { continue }
    $names  += $n
    $blurbs += $cols[1]
    $shapes += $cols[2]
}
if ($names.Count -eq 0) {
    Write-Host 'bench.ps1: no benchmarks selected' -ForegroundColor Red
    exit 2
}

# json_parse reads a generated fixture; make sure it exists before the
# gate runs, or four languages fail identically and the row looks fine.
if (-not (Test-Path -LiteralPath (Join-Path $BenchDir 'data.json'))) {
    & $Python (Join-Path $BenchDir 'gen_data.py') | Out-Null
}

# ── process-start-up floor ───────────────────────────────────────
# What each language costs for a program that does nothing. Subtract it
# from a cell to see the marginal cost of the benchmark itself; a row
# under ~10 ms is mostly this.
$floorDir = Join-Path $BuildDir 'floor'
New-Item -ItemType Directory -Force -Path $floorDir | Out-Null
# LF, no BOM: nurlc reads UTF-8 and the `→` in the signature must survive.
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.nu'), "@ main → i {`n    ^ 0`n}`n", $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.c'),  "int main(void) { return 0; }`n", $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.rs'), "fn main() {}`n", $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.py'), '', $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.js'), '', $Utf8NoBom)

Write-Host "bench.ps1: $($names.Count) benchmark(s), up to $MaxReps rep(s)/cell within $BudgetMs ms, $CompileReps compile(s)/cell"
Write-Host '  measuring the process-start-up floor…'

# The same compile path the benchmarks take, so the compile-time table
# has a floor to subtract too: for NURL that floor is the link against
# stdlib\runtime.o, which every NURL binary pays whatever it does.
$fbase       = Join-Path $floorDir 'floor'
$ccFloorNurl = Compile-Nurl (Join-Path $floorDir 'floor.nu') $fbase
$ccFloorC    = Compile-C    (Join-Path $floorDir 'floor.c')  $fbase
$ccFloorRust = Compile-Rust (Join-Path $floorDir 'floor.rs') $fbase

$floorNurl   = (Time-Cell "$fbase.nurl.exe").Ms
$floorC      = (Time-Cell "$fbase.c.exe").Ms
$floorRust   = (Time-Cell "$fbase.rs.exe").Ms
$floorNode   = (Time-Cell $Node   @((Join-Path $floorDir 'floor.js'))).Ms
$floorPython = (Time-Cell $Python @((Join-Path $floorDir 'floor.py'))).Ms

# ── measure ──────────────────────────────────────────────────────
# Per-benchmark results, collected as parallel arrays in manifest order —
# which is the order the report needs them in anyway.
$rows = @()

function Progress-Line([string]$b, [string]$msg) {
    Write-Host ("`r`e[K  {0,-18} {1}" -f $b, $msg) -NoNewline
}
# Whole-process stdout of one implementation, normalised for comparison.
# C and Python run their stdio in text mode on Windows and emit CRLF; the
# NURL runtime and Node emit LF. Trailing newlines go too, matching what
# bash's $(...) does to the outputs bench.sh compares.
function Run-Output([string]$Exe, [string[]]$Arguments = @()) {
    $r = Measure-Proc -Exe $Exe -Arguments $Arguments -PassThru
    if ($r.Ms -eq 'FAIL' -or $r.Ms -eq 'TIMEOUT') { return '' }
    return (($r.Out -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n"))
}

foreach ($i in 0..($names.Count - 1)) {
    $b    = $names[$i]
    $base = Join-Path $BuildDir $b

    Progress-Line $b 'compiling…'
    $ccNurl = Compile-Nurl (Join-Path $BenchDir "$b.nu") $base
    $ccC    = Compile-C    (Join-Path $BenchDir "$b.c")  $base
    $ccRust = Compile-Rust (Join-Path $BenchDir "$b.rs") $base

    Progress-Line $b 'verifying…'
    $outNurl   = Run-Output "$base.nurl.exe"
    $outC      = Run-Output "$base.c.exe"
    $outRust   = Run-Output "$base.rs.exe"
    $outNode   = Run-Output $Node   @((Join-Path $BenchDir "$b.js"))
    $outPython = Run-Output $Python @((Join-Path $BenchDir "$b.py"))

    $verified = $true
    $details  = @()
    foreach ($pair in @(@('NURL', $outNurl), @('C', $outC), @('Rust', $outRust),
                        @('Node', $outNode), @('Python', $outPython))) {
        $lang = $pair[0]; $got = $pair[1]
        if ($got -cne $outNurl) { $verified = $false }
        if (-not $got)          { $verified = $false }
        $details += "$lang=$(if ($got) { $got } else { '<empty>' })"
    }
    $detail = $details -join ', '

    $row = [ordered]@{
        name = $b; blurb = $blurbs[$i]; measures = $shapes[$i]
        checksum = $outNurl; verified = $verified; detail = $detail
        cc_nurl_fe = $ccNurl.Frontend; cc_nurl = $ccNurl.Total; cc_c = $ccC; cc_rust = $ccRust
    }

    if (-not $verified) {
        Write-Host ("`r`e[K  {0,-18} MISMATCH — {1}" -f $b, $detail) -ForegroundColor Yellow
        foreach ($k in 'nurl', 'c', 'rust', 'node', 'python') {
            $row["ms_$k"] = 'SKIPPED'; $row["reps_$k"] = 0
        }
        $rows += $row
        continue
    }

    Progress-Line $b 'timing NURL…';   $t = Time-Cell "$base.nurl.exe"
    $row.ms_nurl = $t.Ms;   $row.reps_nurl = $t.Reps
    Progress-Line $b 'timing C…';      $t = Time-Cell "$base.c.exe"
    $row.ms_c = $t.Ms;      $row.reps_c = $t.Reps
    Progress-Line $b 'timing Rust…';   $t = Time-Cell "$base.rs.exe"
    $row.ms_rust = $t.Ms;   $row.reps_rust = $t.Reps
    Progress-Line $b 'timing Node…';   $t = Time-Cell $Node   @((Join-Path $BenchDir "$b.js"))
    $row.ms_node = $t.Ms;   $row.reps_node = $t.Reps
    Progress-Line $b 'timing Python…'; $t = Time-Cell $Python @((Join-Path $BenchDir "$b.py"))
    $row.ms_python = $t.Ms; $row.reps_python = $t.Reps

    Write-Host ("`r`e[K  {0,-18} nurl {1,9}  c {2,9}  rust {3,9}  node {4,9}  python {5,9}" -f `
        $b, $row.ms_nurl, $row.ms_c, $row.ms_rust, $row.ms_node, $row.ms_python)
    $rows += $row
}
Write-Host "`r`e[K" -NoNewline

# ── emit ─────────────────────────────────────────────────────────
$Now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')

function JStr([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '\\', '\\\\' -replace '"', '\"')
}
# A cell that is FAIL/TIMEOUT/SKIPPED becomes JSON null, not a string —
# schema 1 says these fields are numbers.
function JNum($v) {
    $s = [string]$v
    if ($s -match '^[0-9.]+$') { return $s }
    return 'null'
}

function Emit-Json {
    $sb = [System.Text.StringBuilder]::new()
    $w  = { param($t) [void]$sb.Append($t); [void]$sb.Append("`n") }
    & $w '{'
    & $w '  "schema": 1,'
    & $w "  ""generated_utc"": ""$(JStr $Now)"","
    & $w "  ""commit"": ""$(JStr $Commit)"","
    & $w "  ""run_url"": ""$(JStr $RunUrl)"","
    & $w '  "host": {'
    & $w "    ""label"": ""$(JStr $HostLabel)"","
    & $w "    ""kernel"": ""$(JStr $HostKernel)"","
    & $w "    ""cpu"": ""$(JStr $HostCpu)"","
    & $w "    ""cores"": $(JNum $HostCores),"
    & $w "    ""mem_kb"": $(JNum $HostMemKb)"
    & $w '  },'
    & $w '  "toolchains": {'
    & $w "    ""nurl"": ""$(JStr $NurlVersion)"","
    & $w "    ""c"": ""$(JStr $ClangVersion)"","
    & $w "    ""rust"": ""$(JStr $RustcVersion)"","
    & $w "    ""node"": ""$(JStr $NodeVersion)"","
    & $w "    ""python"": ""$(JStr $PythonVersion)"""
    & $w '  },'
    & $w '  "settings": {'
    & $w "    ""opt"": ""$(JStr $Opt)"","
    & $w "    ""max_reps"": $MaxReps,"
    & $w "    ""budget_ms"": $BudgetMs,"
    & $w "    ""timeout_s"": $TimeoutS,"
    & $w "    ""compile_reps"": $CompileReps"
    & $w '  },'
    & $w ("  ""floor_ms"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2}, ""node"": {3}, ""python"": {4} }}," -f `
        (JNum $floorNurl), (JNum $floorC), (JNum $floorRust), (JNum $floorNode), (JNum $floorPython))
    & $w ("  ""floor_compile_ms"": {{ ""nurl_frontend"": {0}, ""nurl"": {1}, ""c"": {2}, ""rust"": {3} }}," -f `
        (JNum $ccFloorNurl.Frontend), (JNum $ccFloorNurl.Total), (JNum $ccFloorC), (JNum $ccFloorRust))
    & $w '  "benchmarks": ['
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        & $w '    {'
        & $w "      ""name"": ""$(JStr $r.name)"","
        & $w "      ""blurb"": ""$(JStr $r.blurb)"","
        & $w "      ""measures"": ""$(JStr $r.measures)"","
        & $w "      ""checksum"": ""$(JStr $r.checksum)"","
        & $w "      ""verified"": $(if ($r.verified) { 'true' } else { 'false' }),"
        & $w ("      ""run_ms"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2}, ""node"": {3}, ""python"": {4} }}," -f `
            (JNum $r.ms_nurl), (JNum $r.ms_c), (JNum $r.ms_rust), (JNum $r.ms_node), (JNum $r.ms_python))
        & $w ("      ""reps"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2}, ""node"": {3}, ""python"": {4} }}," -f `
            $r.reps_nurl, $r.reps_c, $r.reps_rust, $r.reps_node, $r.reps_python)
        & $w ("      ""compile_ms"": {{ ""nurl_frontend"": {0}, ""nurl"": {1}, ""c"": {2}, ""rust"": {3} }}" -f `
            (JNum $r.cc_nurl_fe), (JNum $r.cc_nurl), (JNum $r.cc_c), (JNum $r.cc_rust))
        & $w ('    }' + $(if ($i -lt $rows.Count - 1) { ',' } else { '' }))
    }
    & $w '  ]'
    & $w '}'
    return $sb.ToString()
}

# Markdown cell: bold when this language is the fastest in its row.
function MdCell($val, $best) {
    if ([string]$val -eq [string]$best) { return "**$val**" }
    return [string]$val
}
function Fastest-Of([object[]]$vals) {
    $best = ''
    foreach ($v in $vals) {
        $s = [string]$v
        if ($s -match '^[0-9.]+$') {
            if ($best -eq '' -or [double]$s -lt [double]$best) { $best = $s }
        }
    }
    return $best
}
# NURL's clang stage = total − frontend, when both are numbers.
function Link-Ms($total, $fe) {
    if (([string]$total -match '^[0-9.]+$') -and ([string]$fe -match '^[0-9.]+$')) {
        return ('{0:F3}' -f ([double]$total - [double]$fe))
    }
    return 'n/a'
}

function Emit-Md {
    $L = [System.Collections.Generic.List[string]]::new()
    $a = { param($t) $L.Add($t) }

    & $a '# Benchmark results (Windows) — NURL vs C vs Rust vs Node vs Python'
    & $a ''
    & $a "Generated ``$Now`` by ``bench/bench.ps1``, the Windows port of"
    & $a '`bench/bench.sh`. **Do not edit by hand** — the next run overwrites it.'
    & $a 'The machine-readable form of this same run is'
    & $a '[`results/latest-windows.json`](results/latest-windows.json).'
    & $a ''
    & $a 'These are **not** the numbers the landing page publishes: that table comes'
    & $a 'from the Linux CI run in [`RESULTS.md`](RESULTS.md) /'
    & $a '[`results/latest.json`](results/latest.json). Two things differ beyond the'
    & $a 'host — NURL links without `-flto` here, because `build.bat` does not compile'
    & $a '`stdlib/runtime.o` to bitcode, and the link names `-lwinhttp` instead of'
    & $a '`-lm -lpthread`. Both match what a real `nurl.bat` build does on this'
    & $a 'platform, which is the property worth measuring; both make the NURL column'
    & $a 'incomparable to a Linux run cell-for-cell.'
    & $a ''

    & $a '## Environment'
    & $a ''
    & $a '| Item | Value |'
    & $a '|---|---|'
    & $a "| Host | ``$HostLabel`` |"
    & $a "| OS | ``$HostKernel`` |"
    & $a "| CPU | $HostCpu ($HostCores logical cores) |"
    & $a "| Memory | $HostMemKb KiB |"
    & $a "| Commit | ``$Commit`` |"
    if ($RunUrl) { & $a "| CI run | $RunUrl |" }
    & $a "| NURL | ``$NurlVersion`` |"
    & $a "| C | $ClangVersion |"
    & $a "| Rust | $RustcVersion |"
    & $a "| Node | $NodeVersion |"
    & $a "| Python | $PythonVersion |"
    & $a ''
    & $a '| Setting | Value |'
    & $a '|---|---|'
    & $a "| Optimisation | NURL/C ``clang $Opt`` (no LTO), Rust ``-C opt-level=2`` |"
    & $a "| NURL link | ``$($NurlLinkLibs -join ' ')`` |"
    & $a "| Timed runs per cell | up to $MaxReps, adaptive: as many as fit in $BudgetMs ms |"
    & $a "| Timed compiles per cell | $CompileReps (median) |"
    & $a "| Per-run timeout | $TimeoutS s |"
    & $a ''

    & $a '## 1. Run time (median wall clock, ms — lower is better)'
    & $a ''
    & $a 'Whole-process wall clock, start-up included. Every implementation of a'
    & $a 'row prints the same line (section 3), so these are five timings of the'
    & $a 'same computation. **Bold** is the fastest cell in the row.'
    & $a ''
    & $a '| Benchmark | NURL | C | Rust | Node | Python |'
    & $a '|---|---:|---:|---:|---:|---:|'
    & $a ("| _(floor: empty program)_ | _{0}_ | _{1}_ | _{2}_ | _{3}_ | _{4}_ |" -f `
        $floorNurl, $floorC, $floorRust, $floorNode, $floorPython)
    foreach ($r in $rows) {
        $best = Fastest-Of @($r.ms_nurl, $r.ms_c, $r.ms_rust, $r.ms_node, $r.ms_python)
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} |" -f $r.name,
            (MdCell $r.ms_nurl $best), (MdCell $r.ms_c $best), (MdCell $r.ms_rust $best),
            (MdCell $r.ms_node $best), (MdCell $r.ms_python $best))
    }
    & $a ''

    & $a '## 2. Compile time (median, ms)'
    & $a ''
    & $a "NURL's compile is two stages: ``nurlc.exe`` emits LLVM IR, then ``clang``"
    & $a 'lowers and links it against `stdlib\runtime.o`. **NURL total** is the'
    & $a 'number comparable to the C and Rust columns. The floor row is what each'
    & $a 'toolchain costs for a program that does nothing — for NURL that is'
    & $a 'dominated by the link every NURL binary pays for, so subtract it to read'
    & $a 'the marginal cost of the benchmark itself. Node and Python have no column'
    & $a 'here: they compile at run time, inside their own cells above.'
    & $a ''
    & $a '| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |'
    & $a '|---|---:|---:|---:|---:|---:|'
    & $a ("| _(floor: empty program)_ | _{0}_ | _{1}_ | _**{2}**_ | _{3}_ | _{4}_ |" -f `
        $ccFloorNurl.Frontend, (Link-Ms $ccFloorNurl.Total $ccFloorNurl.Frontend),
        $ccFloorNurl.Total, $ccFloorC, $ccFloorRust)
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | **{3}** | {4} | {5} |" -f $r.name,
            $r.cc_nurl_fe, (Link-Ms $r.cc_nurl $r.cc_nurl_fe), $r.cc_nurl, $r.cc_c, $r.cc_rust)
    }
    & $a ''

    & $a '## 3. Correctness gate'
    & $a ''
    & $a 'Each row is timed only when all five implementations print the same'
    & $a 'line. A speed number for a program computing something else is worthless,'
    & $a 'so a mismatch drops the row out of the tables above rather than being'
    & $a 'reported as a fast cell. Comparison is on the text, with CRLF normalised'
    & $a "to LF — C's and Python's stdio are in text mode on Windows and the NURL"
    & $a 'runtime writes bytes, which is a line-ending difference and nothing more.'
    & $a ''
    & $a '| Benchmark | Output | Verdict |'
    & $a '|---|---|---|'
    foreach ($r in $rows) {
        if ($r.verified) {
            & $a ("| ``{0}`` | ``{1}`` | identical across 5 languages |" -f $r.name, $r.checksum)
        } else {
            & $a ("| ``{0}`` | — | **MISMATCH** — {1} |" -f $r.name, $r.detail)
        }
    }
    & $a ''

    & $a '## 4. Reading the numbers'
    & $a ''
    & $a '* A cell near the floor row is mostly process start-up, DLL loading and'
    & $a '  page faults rather than the benchmark. The rows worth comparing are the'
    & $a '  ones in the tens of milliseconds and up. The Windows floor is higher'
    & $a '  than the Linux one across the board — loader work, not the language.'
    & $a '* All three compiled back ends are LLVM-based and all three are allowed to'
    & $a '  be clever: LLVM will fold an affine recurrence or unroll a loop by a'
    & $a '  different factor in each language. A cell measures optimised throughput'
    & $a '  of the same algorithm, not the source-level iteration count.'
    & $a '* Ten of the fifteen benchmarks are defined over 64-bit unsigned integers.'
    & $a '  Python has arbitrary-precision integers and masks; JS has no 64-bit'
    & $a '  integer at all, so those rows use `BigInt` where the algorithm genuinely'
    & $a '  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each'
    & $a '  file says which and why. That gap *is* part of what this table reports.'
    & $a '* `json_parse` is the one row whose gate is "every parser accepted the'
    & $a '  document" rather than a structural checksum: each language uses the'
    & $a '  parser in its own box (Python `json`, Node `JSON.parse`, NURL'
    & $a "  ``stdlib/ext/json.nu``), and C and Rust — whose boxes are empty — carry a"
    & $a '  small hand-written recursive-descent parser in the benchmark file.'
    & $a '* Wall clock on a machine that was not quiesced drifts a few per cent'
    & $a '  between runs, and more on a laptop that can thermally throttle or drop'
    & $a '  to a power-saving governor mid-suite. Compare deltas between runs on the'
    & $a '  same box, not absolutes across machines — and never across OSes here,'
    & $a '  for the link-line reason at the top of this file.'

    return (($L -join "`n") + "`n")
}

if ($Stdout) {
    Write-Output (Emit-Md)
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Json), (Split-Path -Parent $Md) | Out-Null
    # LF, UTF-8 without BOM — the same bytes bench.sh writes, so a diff
    # against a Linux artefact shows numbers and not line endings.
    [System.IO.File]::WriteAllText($Json, (Emit-Json), $Utf8NoBom)
    [System.IO.File]::WriteAllText($Md,   (Emit-Md),   $Utf8NoBom)
    Write-Host "wrote $Json"
    Write-Host "wrote $Md"
}

# A mismatched row is a failure of the suite, not a slow benchmark.
foreach ($r in $rows) {
    if (-not $r.verified) {
        Write-Host 'bench.ps1: at least one row failed the correctness gate' -ForegroundColor Red
        exit 1
    }
}
exit 0
