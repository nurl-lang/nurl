#!/usr/bin/env pwsh
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  bench/wasmbench.ps1 — the Windows wasm benchmark runner. A port of
#  bench/wasmbench.sh: same corpus, same manifest, same protocol, the same
#  ten cells per row, the same two artefacts — written the way bench.ps1
#  ports bench.sh.
#
#  Every benchmark in bench/manifest.tsv is implemented in NURL, C and
#  Rust. Each of those three is compiled twice — native and wasm32-wasi —
#  and every wasm module is then run on two runtimes:
#
#    reference wasmtime   The external Bytecode Alliance runtime (Cranelift
#                         JIT): the cost of the *target*, with compiler
#                         quality controlled for.
#    packages/nwasm       `nwasm`, the WebAssembly runtime written in pure
#                         NURL: the cost of *this runtime*.
#
#  Ten timed cells per row — 3 languages x {native, JIT, interpreter}, plus
#  the NURL module relinked with --no-gc-sections — all gated on printing
#  the same line as the native NURL binary.
#
#  Artefacts (Windows names, so a local run never overwrites the Linux CI
#  report that wasm-bench.yml commits):
#    bench/results/wasm-latest-windows.json   machine-readable
#    bench/WASMRESULTS-WINDOWS.md             the same run for humans
#  and at -Scale N > 1 wasm-xN-windows.json / WASMRESULTS-WINDOWS-xN.md.
#
#  Usage:
#      pwsh bench\wasmbench.ps1                   # full suite, write both files
#      pwsh bench\wasmbench.ps1 -Quick            # 1 rep/cell, for a smoke test
#      pwsh bench\wasmbench.ps1 -Bench lcg,sieve
#      pwsh bench\wasmbench.ps1 -NwasmAllLangs    # + C/Rust on the interpreter
#      pwsh bench\wasmbench.ps1 -Scale 100        # every benchmark does 100x the work
#      pwsh bench\wasmbench.ps1 -Stdout           # print the report, touch nothing
#
#  -Scale N (default: $env:BENCH_SCALE, else 1) multiplies every
#  benchmark's workload by N before it is compiled: each source defines
#  `BENCH_SCALE` once (1), and a copy with that one number rewritten is
#  what gets compiled — the same rewrite wasmbench.sh and bench.sh do.
#
#  Requires build\nurlc.exe + stdlib\runtime.o (build.bat), clang, rustc +
#  the wasm32-wasip1 target, zig ($env:NURL_ZIG, the toolchain's bundled
#  %NURL_HOME%\zig, or PATH) and the external reference wasmtime
#  ($env:WASMTIME, PATH, or %USERPROFILE%\.wasmtime\bin). A missing
#  toolchain is a hard error. `wasmbuilder` and `nwasm` are compiled from
#  packages\ by this script (through nurl.bat), so they always match the
#  repo they are measuring.
#
#  ── Deliberate deviations from wasmbench.sh, and why ───────────
#
#  * The native NURL link is bench.ps1's: no -flto (build.bat does not
#    compile stdlib\runtime.o to bitcode), -lwinhttp plus the feature libs
#    in stdlib\runtime.winlibs instead of -lm -lpthread. The wasm cells
#    are unaffected — wasmbuilder links its own runtime.wasm.o.
#  * Outputs are compared with CRLF normalised to LF, as in bench.ps1.
#  * The script also runs under pwsh on Linux and macOS (`$IsWindows` picks
#    the executable suffix, the nurl driver and the native link line), which
#    is how it was exercised — the Windows-specific branches are the
#    untested part.
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
    # Per-run wall-clock cap, seconds (the interpreter needs room).
    [int]$TimeoutS = 900,
    # Timed compiles per compiled language (median of).
    [int]$CompileReps = 3,
    [string]$Json,
    [string]$Md,
    # Print the Markdown report to stdout and write nothing.
    [switch]$Stdout,
    # Also run the C and Rust modules on nwasm (roughly triples the run).
    [switch]$NwasmAllLangs,
    # 1 rep/cell, 1 compile/cell — a smoke test of the harness itself.
    [switch]$Quick,
    # Workload multiplier: BENCH_SCALE in every NURL, C and Rust source.
    [string]$Scale = $(if ($env:BENCH_SCALE) { $env:BENCH_SCALE } else { '1' })
)
$ErrorActionPreference = 'Stop'

$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
# Native binaries: `.exe` on Windows, `.bin` elsewhere as in wasmbench.sh —
# a bare `<name>.rs` would collide with the floor's own source file.
$ExeSuffix = if ($OnWindows) { '.exe' } else { '.bin' }
# What the nurl driver itself appends to an output name (nurl.bat: .exe).
$PkgSuffix = if ($OnWindows) { '.exe' } else { '' }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root      = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$BenchDir  = Join-Path $Root 'bench'
$BuildDir  = Join-Path $BenchDir '_wasmbuild'
$Manifest  = Join-Path $BenchDir 'manifest.tsv'

# ── settings ─────────────────────────────────────────────────────
$MaxReps      = $Reps
$Opt          = '-O2'
$WasmTargetC  = 'wasm32-wasi'      # zig cc's spelling
$WasmTargetRs = 'wasm32-wasip1'    # rustc's spelling
if ($Quick) { $MaxReps = 1; $BudgetMs = 1; $CompileReps = 1 }
if ($Scale -notmatch '^[1-9][0-9]{0,8}$') {
    Write-Host "wasmbench.ps1: -Scale (or BENCH_SCALE) wants a positive integer below 10^9, got '$Scale'" -ForegroundColor Red
    exit 2
}
$ScaleN = [int64]$Scale
# A xN run is its own report: the x1 table stays the reference one.
if ($ScaleN -eq 1) {
    if (-not $Json) { $Json = Join-Path $BenchDir (Join-Path 'results' 'wasm-latest-windows.json') }
    if (-not $Md)   { $Md   = Join-Path $BenchDir 'WASMRESULTS-WINDOWS.md' }
} else {
    if (-not $Json) { $Json = Join-Path $BenchDir (Join-Path 'results' "wasm-x$Scale-windows.json") }
    if (-not $Md)   { $Md   = Join-Path $BenchDir "WASMRESULTS-WINDOWS-x$Scale.md" }
}

# nurlc resolves `$ "stdlib/..."` imports relative to its working
# directory, and json_parse opens bench/data.json through a `--dir .`
# preopen, so every compile and every run happens from $Root.
Set-Location $Root
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# ── roster ───────────────────────────────────────────────────────
# -File invocation hands `-Bench lcg,sieve` over as ONE string; split it so
# the documented spelling works from pwsh, cmd and a PowerShell prompt.
if ($Bench) {
    $Bench = @($Bench | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
}
# A fourth manifest column, when present, lists the row's bench.sh
# languages; every row has NURL, C and Rust, which is all this suite runs.
$names = @(); $blurbs = @(); $shapes = @()
foreach ($line in [System.IO.File]::ReadAllLines($Manifest)) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    $cols = $line -split "`t"
    if ($cols.Count -lt 3) { continue }
    $n = $cols[0].Trim()
    if (-not $n) { continue }
    if ($Bench -and ($Bench -notcontains $n)) { continue }
    $names += $n; $blurbs += $cols[1]; $shapes += $cols[2]
}
if ($names.Count -eq 0) {
    Write-Host 'wasmbench.ps1: no benchmarks selected' -ForegroundColor Red
    exit 2
}

# ── toolchain detection ──────────────────────────────────────────
$Nurlc   = Join-Path $Root (Join-Path 'build' "nurlc$PkgSuffix")
$Runtime = Join-Path $Root (Join-Path 'stdlib' 'runtime.o')
$NurlHome = if ($env:NURL_HOME) { $env:NURL_HOME } elseif ($OnWindows) { Join-Path $env:USERPROFILE '.nurl' } else { Join-Path $HOME '.nurl' }

function Resolve-Exe([string]$name, [string[]]$candidates = @()) {
    $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if ($c) { return $c.Source }
    foreach ($p in $candidates) { if ($p -and (Test-Path -LiteralPath $p)) { return (Resolve-Path -LiteralPath $p).Path } }
    return $null
}
function First-Line([string]$s) {
    if (-not $s) { return '' }
    return (($s -replace "`r`n", "`n") -split "`n")[0].Trim()
}
# First line of `<exe> <arg>`, or $null when the thing cannot actually run
# (a rustup shim with no toolchain resolves fine and fails every compile).
function Get-ToolVersion([string]$exe, [string]$arg = '--version') {
    if (-not $exe) { return $null }
    try {
        $v = First-Line (& $exe $arg 2>&1 | Out-String)
        if ($LASTEXITCODE -eq 0 -and $v) { return $v }
    } catch {}
    return $null
}

$Clang = Resolve-Exe ($env:CLANG ? $env:CLANG : 'clang') @(
             $env:CLANG,
             "$env:ProgramFiles\LLVM\bin\clang.exe",
             "${env:ProgramFiles(x86)}\LLVM\bin\clang.exe")
$Rustc = Resolve-Exe 'rustc' @($(if ($OnWindows) { "$env:USERPROFILE\.cargo\bin\rustc.exe" } else { "$HOME/.cargo/bin/rustc" }))
# zig carries its own wasi-libc and wasm-ld; same discovery order the
# wasmbuilder package uses, so both find the same zig.
$Zig = if ($env:NURL_ZIG) { $env:NURL_ZIG } else {
    Resolve-Exe 'zig' @((Join-Path $NurlHome (Join-Path 'zig' "zig$PkgSuffix")))
}
# The reference runtime: not vendored anywhere in this repo on purpose.
$Wasmtime = if ($env:WASMTIME) { $env:WASMTIME } else {
    Resolve-Exe 'wasmtime' @($(if ($OnWindows) { "$env:USERPROFILE\.wasmtime\bin\wasmtime.exe" } else { "$HOME/.wasmtime/bin/wasmtime" }))
}

$ClangVersion    = Get-ToolVersion $Clang
$RustcVersion    = Get-ToolVersion $Rustc
$ZigVersion      = Get-ToolVersion $Zig 'version'
$WasmtimeVersion = Get-ToolVersion $Wasmtime

$missing = @()
if (-not (Test-Path -LiteralPath $Nurlc) -or -not (Test-Path -LiteralPath $Runtime)) {
    $missing += $(if ($OnWindows) { 'nurlc + stdlib\runtime.o (run build.bat)' } else { 'nurlc (run ./build.sh)' })
}
if     (-not $Clang)           { $missing += 'clang (install LLVM, or set CLANG=<path>)' }
elseif (-not $ClangVersion)    { $missing += "clang at $Clang does not run" }
if     (-not $Rustc)           { $missing += 'rustc (install Rust: winget install Rustlang.Rustup)' }
elseif (-not $RustcVersion)    { $missing += "rustc at $Rustc does not run (a rustup shim with no toolchain? run: rustup default stable)" }
if     (-not $Zig)             { $missing += 'zig (install the NURL toolchain, or set NURL_ZIG=<path>)' }
elseif (-not $ZigVersion)      { $missing += "zig at $Zig does not run" }
if     (-not $Wasmtime)        { $missing += 'wasmtime (https://wasmtime.dev, or set WASMTIME=<path>)' }
elseif (-not $WasmtimeVersion) { $missing += "wasmtime at $Wasmtime does not run" }
if ($Rustc -and $RustcVersion) {
    & $Rustc --print target-libdir --target $WasmTargetRs *> $null
    if ($LASTEXITCODE -ne 0) { $missing += "rust std for $WasmTargetRs (rustup target add $WasmTargetRs)" }
}
if ($missing.Count -gt 0) {
    Write-Host "wasmbench.ps1: missing toolchain: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}
$ZigVersion = "zig $ZigVersion"

# The native NURL link line — exactly what bench.ps1 / bench.sh use on this
# OS, so the native columns match a normal `nurl.bat` / `nurl.sh` build.
if ($OnWindows) {
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
    $NurlLinkPre  = @($Opt)
    $NurlLinkLibs = @('-lwinhttp') + $WinLibs
    $CLibs        = @()
} else {
    $extra = @()
    foreach ($pair in 'runtime.curl:libcurl', 'runtime.openssl:openssl', 'runtime.sqlite3:sqlite3',
                      'runtime.pq:libpq', 'runtime.z:zlib', 'runtime.zstd:libzstd') {
        $marker, $pc = $pair -split ':'
        if (Test-Path -LiteralPath (Join-Path $Root "stdlib/$marker")) {
            $extra += @((& pkg-config --libs $pc 2>$null | Out-String).Trim() -split '\s+' | Where-Object { $_ })
        }
    }
    $NurlLinkPre  = @($Opt, '-flto', '-Wl,--as-needed')
    $NurlLinkLibs = @('-lm', '-lpthread') + $extra
    $CLibs        = @('-lm')
}

# ── build the two packages under test ────────────────────────────
# wasmbuilder compiles the wasm; nwasm runs it. Both are rebuilt from this
# repo, never taken from an installed toolchain. NURL_SPLIT=0 for the same
# reason wasmbench.sh gives: nwasm is the subject of section 3 and the
# reference runtime it is measured against is a release build.
$Wasmbuilder = Join-Path $BuildDir "wasmbuilder$PkgSuffix"
$Nwasm       = Join-Path $BuildDir "nwasm$PkgSuffix"
Write-Host '  building packages/wasmbuilder and packages/nwasm …'
$env:NURL_SPLIT = '0'
foreach ($pkg in 'wasmbuilder', 'nwasm') {
    $src  = Join-Path 'packages' (Join-Path $pkg (Join-Path 'src' 'main.nu'))
    $out  = Join-Path $BuildDir $pkg      # nurl.bat appends .exe itself
    $log  = "$out.buildlog"
    if ($OnWindows) {
        & cmd /c "`"$(Join-Path $Root 'nurl.bat')`" `"$src`" `"$out`"" *> $log
    } else {
        & (Join-Path $Root 'nurl.sh') $src $out *> $log
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath "$out$PkgSuffix")) {
        Write-Host "wasmbench.ps1: failed to build packages/$pkg — see $log" -ForegroundColor Red
        exit 1
    }
}
Remove-Item Env:\NURL_SPLIT -ErrorAction SilentlyContinue

# wasmbuilder resolves nurlc and the stdlib C sources from the environment;
# point both at this repo so the wasm modules and the native binaries come
# out of the same compiler. Then warm its runtime.wasm.o cache outside the
# timed region.
$env:NURLC       = $Nurlc
$env:NURL_STDLIB = $Root
& $Wasmbuilder --doctor *> $null

$NurlVersion = Get-ToolVersion $Nurlc
if (-not $NurlVersion) { $NurlVersion = First-Line (& git -C $Root describe --tags --always --dirty 2>$null | Out-String) }
$WasmbuilderVersion = Get-ToolVersion $Wasmbuilder
$NwasmVersion       = Get-ToolVersion $Nwasm

# Host facts, as bench.ps1 gathers them (and uname-style off Windows).
$Arch       = if ($env:PROCESSOR_ARCHITECTURE) { $env:PROCESSOR_ARCHITECTURE } else { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
$HostKernel = "$([System.Runtime.InteropServices.RuntimeInformation]::OSDescription) $Arch"
$HostCpu    = $Arch
$HostCores  = [Environment]::ProcessorCount
$HostMemKb  = 0
if ($OnWindows) {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.Name) { $HostCpu = $cpu.Name.Trim() }
        if ($cpu.NumberOfLogicalProcessors) { $HostCores = [int]$cpu.NumberOfLogicalProcessors }
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.TotalPhysicalMemory) { $HostMemKb = [int64]($cs.TotalPhysicalMemory / 1024) }
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if ($os.Caption) { $HostKernel = "$($os.Caption.Trim()) $($os.Version) $Arch" }
    } catch {}
} else {
    try {
        $m = Select-String -Path '/proc/cpuinfo' -Pattern '^model name\s*:\s*(.*)$' -ErrorAction Stop | Select-Object -First 1
        if ($m) { $HostCpu = $m.Matches[0].Groups[1].Value.Trim() }
        $k = Select-String -Path '/proc/meminfo' -Pattern '^MemTotal:\s*(\d+)' -ErrorAction Stop | Select-Object -First 1
        if ($k) { $HostMemKb = [int64]$k.Matches[0].Groups[1].Value }
    } catch {}
}
$HostLabel = if ($env:BENCH_HOST_LABEL) { $env:BENCH_HOST_LABEL } else { "$(if ($OnWindows) { 'Windows' } else { [System.Runtime.InteropServices.RuntimeInformation]::OSDescription.Split(' ')[0] }) $Arch" }
$Commit    = First-Line (& git -C $Root rev-parse HEAD 2>$null | Out-String)
if (-not $Commit) { $Commit = 'unknown' }
$RunUrl    = if ($env:BENCH_RUN_URL) { $env:BENCH_RUN_URL } else { '' }

# ── timing helpers ───────────────────────────────────────────────
# Identical to bench.ps1's: Stopwatch around exactly the child process,
# stdout/stderr drained asynchronously, the clock stopped on exit.
function Measure-Proc {
    param(
        [string]$Exe,
        [string[]]$Arguments = @(),
        [string]$StdoutFile,
        [switch]$PassThru
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    foreach ($a in $Arguments) { [void]$psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory       = $Root
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding  = [System.Text.UTF8Encoding]::new($false)
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    if ($OnWindows) { $psi.Environment['__COMPAT_LAYER'] = 'RunAsInvoker' }

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
# Adaptive repetitions: one run, then as many as fit in BudgetMs, capped
# at MaxReps. Returns @{ Ms = <median or FAIL/TIMEOUT>; Reps = <n> }.
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
# Median of CompileReps timings of one command, or FAIL.
function Time-Compile([string]$Exe, [string[]]$Arguments, [string]$StdoutFile) {
    $out = @()
    for ($r = 0; $r -lt $CompileReps; $r++) {
        $t = Time-Ms $Exe $Arguments $StdoutFile
        if ($t -eq 'FAIL' -or $t -eq 'TIMEOUT') { return 'FAIL' }
        $out += $t
    }
    return (Median $out)
}

# ── compile helpers ──────────────────────────────────────────────
function Compile-NurlNative([string]$src, [string]$outbase) {
    $ll = "$outbase.ll"; $bin = "$outbase.nurl$ExeSuffix"
    $fe = @(); $tot = @()
    for ($r = 0; $r -lt $CompileReps; $r++) {
        $f = Time-Ms $Nurlc @($src) -StdoutFile $ll
        if ($f -eq 'FAIL' -or $f -eq 'TIMEOUT') { return @{ Frontend = 'FAIL'; Total = 'FAIL' } }
        $l = Time-Ms $Clang ($NurlLinkPre + @($ll, $Runtime) + $NurlLinkLibs + @('-o', $bin))
        if ($l -eq 'FAIL' -or $l -eq 'TIMEOUT') { return @{ Frontend = 'FAIL'; Total = 'FAIL' } }
        $fe += $f; $tot += ('{0:F3}' -f ([double]$f + [double]$l))
    }
    return @{ Frontend = (Median $fe); Total = (Median $tot) }
}
# The whole wasmbuilder pipeline in one number (nurlc, the IR rewriter,
# zig cc against wasi-libc and the cached runtime.wasm.o).
function Compile-NurlWasm([string]$src, [string]$outbase) {
    return (Time-Compile $Wasmbuilder @('-q', $src, '-o', "$outbase.nu.wasm"))
}
# The same with --no-gc-sections, the escape hatch section 5 prices.
function Compile-NurlWasmNogc([string]$src, [string]$outbase) {
    return (Time-Compile $Wasmbuilder @('-q', '--no-gc-sections', $src, '-o', "$outbase.nunogc.wasm"))
}
function Compile-CNative([string]$src, [string]$outbase) {
    return (Time-Compile $Clang (@($Opt, $src) + $CLibs + @('-o', "$outbase.c$ExeSuffix")))
}
function Compile-CWasm([string]$src, [string]$outbase) {
    return (Time-Compile $Zig @('cc', "--target=$WasmTargetC", $Opt, $src, '-lm', '-o', "$outbase.c.wasm"))
}
function Compile-RustNative([string]$src, [string]$outbase) {
    return (Time-Compile $Rustc @('-C', 'opt-level=2', $src, '-o', "$outbase.rs$ExeSuffix"))
}
function Compile-RustWasm([string]$src, [string]$outbase) {
    return (Time-Compile $Rustc @('--target', $WasmTargetRs, '-C', 'opt-level=2', $src, '-o', "$outbase.rs.wasm"))
}
function FSize([string]$p) {
    if (Test-Path -LiteralPath $p) { return (Get-Item -LiteralPath $p).Length }
    return 0
}

# ── workload scale ───────────────────────────────────────────────
# The one-line contract every source carries; xN compiles copies with that
# one number rewritten. A source without exactly one such line stops the run.
$ScalePatterns = @{
    nu = @('(?m)^(\s*: u64 BENCH_SCALE )1\r?$',     ('${1}' + $Scale))
    c  = @('(?m)^(#define BENCH_SCALE )1ULL\r?$',    ('${1}' + $Scale + 'ULL'))
    rs = @('(?m)^(const BENCH_SCALE: u64 = )1;\r?$', ('${1}' + $Scale + ';'))
}
$SrcDir = Join-Path $BuildDir "src-x$Scale"
function Src-For([string]$b, [string]$ext) {
    $in = Join-Path $BenchDir "$b.$ext"
    if ($ScaleN -eq 1) { return $in }
    $pat = $ScalePatterns[$ext]
    $out = Join-Path $SrcDir "$b.$ext"
    $text = [System.IO.File]::ReadAllText($in)
    [System.IO.File]::WriteAllText($out, ([regex]::Replace($text, $pat[0], $pat[1])), $Utf8NoBom)
    return $out
}
if ($ScaleN -ne 1) {
    New-Item -ItemType Directory -Force -Path $SrcDir | Out-Null
    $bad = @()
    foreach ($b in $names) {
        foreach ($ext in 'nu', 'c', 'rs') {
            $text = [System.IO.File]::ReadAllText((Join-Path $BenchDir "$b.$ext"))
            if ([regex]::Matches($text, $ScalePatterns[$ext][0]).Count -ne 1) { $bad += "$b.$ext" }
        }
    }
    if ($bad.Count -gt 0) {
        Write-Host "wasmbench.ps1: -Scale $Scale needs exactly one BENCH_SCALE definition in: $($bad -join ' ')" -ForegroundColor Red
        exit 2
    }
}

# json_parse reads a generated fixture; make sure it exists before the gate.
if (-not (Test-Path -LiteralPath (Join-Path $BenchDir 'data.json'))) {
    $py = Resolve-Exe 'python3'
    if (-not $py) { $py = Resolve-Exe 'python' }
    if (-not $py) { $py = Resolve-Exe 'py' @('C:\Windows\py.exe') }
    if (-not $py) {
        Write-Host 'wasmbench.ps1: bench/data.json is missing and no python is installed to run gen_data.py' -ForegroundColor Red
        exit 1
    }
    & $py (Join-Path $BenchDir 'gen_data.py') | Out-Null
}

# Every wasm run gets `--dir .`; the reference runtime's module cache is
# off (`-C cache=n`) so every cell is decode + compile + run, exactly as
# wasmbench.sh explains.
$RefArgs   = @('run', '-C', 'cache=n', '--dir', '.')
$NwasmArgs = @('run', '--dir', '.')

# ── process-start-up floor ───────────────────────────────────────
$floorDir = Join-Path $BuildDir 'floor'
New-Item -ItemType Directory -Force -Path $floorDir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.nu'), "@ main → i {`n    ^ 0`n}`n", $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.c'),  "int main(void) { return 0; }`n", $Utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $floorDir 'floor.rs'), "fn main() {}`n", $Utf8NoBom)
$fb = Join-Path $floorDir 'floor'

Write-Host "wasmbench.ps1: $($names.Count) benchmark(s), up to $MaxReps rep(s)/cell within $BudgetMs ms, $CompileReps compile(s)/cell, x$Scale"
Write-Host '  measuring the floor …'
$fl = @{}
$ccFloorNurl          = Compile-NurlNative (Join-Path $floorDir 'floor.nu') $fb
$fl.cc_nurl_wasm      = Compile-NurlWasm (Join-Path $floorDir 'floor.nu') $fb
$fl.cc_nurl_wasm_nogc = Compile-NurlWasmNogc (Join-Path $floorDir 'floor.nu') $fb
$fl.cc_c              = Compile-CNative (Join-Path $floorDir 'floor.c') $fb
$fl.cc_c_wasm         = Compile-CWasm (Join-Path $floorDir 'floor.c') $fb
$fl.cc_rust           = Compile-RustNative (Join-Path $floorDir 'floor.rs') $fb
$fl.cc_rust_wasm      = Compile-RustWasm (Join-Path $floorDir 'floor.rs') $fb
$fl.cc_nurl_fe = $ccFloorNurl.Frontend; $fl.cc_nurl = $ccFloorNurl.Total

$fl.nurl         = (Time-Cell "$fb.nurl$ExeSuffix").Ms
$fl.c            = (Time-Cell "$fb.c$ExeSuffix").Ms
$fl.rust         = (Time-Cell "$fb.rs$ExeSuffix").Ms
$fl.nurl_ref     = (Time-Cell $Wasmtime ($RefArgs + @("$fb.nu.wasm"))).Ms
$fl.nurl_ref_nogc = (Time-Cell $Wasmtime ($RefArgs + @("$fb.nunogc.wasm"))).Ms
$fl.c_ref        = (Time-Cell $Wasmtime ($RefArgs + @("$fb.c.wasm"))).Ms
$fl.rust_ref     = (Time-Cell $Wasmtime ($RefArgs + @("$fb.rs.wasm"))).Ms
$fl.nurl_nw      = (Time-Cell $Nwasm ($NwasmArgs + @("$fb.nu.wasm"))).Ms
if ($NwasmAllLangs) {
    $fl.c_nw    = (Time-Cell $Nwasm ($NwasmArgs + @("$fb.c.wasm"))).Ms
    $fl.rust_nw = (Time-Cell $Nwasm ($NwasmArgs + @("$fb.rs.wasm"))).Ms
} else { $fl.c_nw = 'SKIPPED'; $fl.rust_nw = 'SKIPPED' }
$fl.sz_nurl_wasm      = FSize "$fb.nu.wasm"
$fl.sz_nurl_wasm_nogc = FSize "$fb.nunogc.wasm"

# ── measure ──────────────────────────────────────────────────────
$rows = @()
function Progress-Line([string]$b, [string]$msg) {
    Write-Host ("`r`e[K  {0,-18} {1}" -f $b, $msg) -NoNewline
}
function Run-Output([string]$Exe, [string[]]$Arguments = @()) {
    $r = Measure-Proc -Exe $Exe -Arguments $Arguments -PassThru
    if ($r.Ms -eq 'FAIL' -or $r.Ms -eq 'TIMEOUT') { return '' }
    return (($r.Out -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n"))
}
$cellKeys = 'nurl', 'c', 'rust', 'nurl_ref', 'c_ref', 'rust_ref', 'nurl_ref_nogc', 'nurl_nw', 'c_nw', 'rust_nw'

foreach ($i in 0..($names.Count - 1)) {
    $b    = $names[$i]
    $base = Join-Path $BuildDir $b
    $srcNu = Src-For $b 'nu'; $srcC = Src-For $b 'c'; $srcRs = Src-For $b 'rs'

    Progress-Line $b 'compiling native…'
    $ccNurl = Compile-NurlNative $srcNu $base
    $row = [ordered]@{
        name = $b; blurb = $blurbs[$i]; measures = $shapes[$i]
        cc_nurl_fe = $ccNurl.Frontend; cc_nurl = $ccNurl.Total
        cc_c = (Compile-CNative $srcC $base); cc_rust = (Compile-RustNative $srcRs $base)
    }
    Progress-Line $b 'compiling wasm…'
    $row.cc_nurl_wasm      = Compile-NurlWasm $srcNu $base
    $row.cc_nurl_wasm_nogc = Compile-NurlWasmNogc $srcNu $base
    $row.cc_c_wasm         = Compile-CWasm $srcC $base
    $row.cc_rust_wasm      = Compile-RustWasm $srcRs $base

    $row.sz_nurl           = FSize "$base.nurl$ExeSuffix"
    $row.sz_nurl_wasm      = FSize "$base.nu.wasm"
    $row.sz_nurl_wasm_nogc = FSize "$base.nunogc.wasm"
    $row.sz_c              = FSize "$base.c$ExeSuffix"
    $row.sz_c_wasm         = FSize "$base.c.wasm"
    $row.sz_rust           = FSize "$base.rs$ExeSuffix"
    $row.sz_rust_wasm      = FSize "$base.rs.wasm"

    # ── the gate: ten cells, one expected line (the native NURL output) ──
    Progress-Line $b 'verifying native + JIT…'
    $outNurl = Run-Output "$base.nurl$ExeSuffix"
    $pairs = @(
        @('NURL',           $outNurl),
        @('C',              (Run-Output "$base.c$ExeSuffix")),
        @('Rust',           (Run-Output "$base.rs$ExeSuffix")),
        @('NURL/wasm',      (Run-Output $Wasmtime ($RefArgs + @("$base.nu.wasm")))),
        @('C/wasm',         (Run-Output $Wasmtime ($RefArgs + @("$base.c.wasm")))),
        @('Rust/wasm',      (Run-Output $Wasmtime ($RefArgs + @("$base.rs.wasm")))),
        @('NURL/wasm+nogc', (Run-Output $Wasmtime ($RefArgs + @("$base.nunogc.wasm")))))
    Progress-Line $b 'verifying interpreter…'
    $pairs += ,@('NURL/nwasm', (Run-Output $Nwasm ($NwasmArgs + @("$base.nu.wasm"))))
    if ($NwasmAllLangs) {
        $pairs += ,@('C/nwasm',    (Run-Output $Nwasm ($NwasmArgs + @("$base.c.wasm"))))
        $pairs += ,@('Rust/nwasm', (Run-Output $Nwasm ($NwasmArgs + @("$base.rs.wasm"))))
    }
    $verified = $true; $details = @()
    foreach ($pair in $pairs) {
        # An empty line fails the gate even when every cell agrees on it.
        if ($pair[1] -cne $outNurl -or -not $pair[1]) {
            $verified = $false
            $details += "$($pair[0])=$(if ($pair[1]) { $pair[1] } else { '<empty>' })"
        }
    }
    $row.checksum = $outNurl; $row.verified = $verified
    $row.detail = if ($details.Count) { $details -join ', ' } else { "all cells printed $outNurl" }

    if (-not $verified) {
        Write-Host ("`r`e[K  {0,-18} MISMATCH — {1}" -f $b, $row.detail) -ForegroundColor Yellow
        foreach ($k in $cellKeys) { $row["ms_$k"] = 'SKIPPED'; $row["reps_$k"] = 0 }
        $rows += $row
        continue
    }

    $plan = @(
        @('nurl',          'NURL native',           "$base.nurl$ExeSuffix", @()),
        @('c',             'C native',              "$base.c$ExeSuffix",    @()),
        @('rust',          'Rust native',           "$base.rs$ExeSuffix",   @()),
        @('nurl_ref',      'NURL wasm (JIT)',       $Wasmtime, ($RefArgs + @("$base.nu.wasm"))),
        @('c_ref',         'C wasm (JIT)',          $Wasmtime, ($RefArgs + @("$base.c.wasm"))),
        @('rust_ref',      'Rust wasm (JIT)',       $Wasmtime, ($RefArgs + @("$base.rs.wasm"))),
        @('nurl_ref_nogc', 'NURL wasm+nogc (JIT)',  $Wasmtime, ($RefArgs + @("$base.nunogc.wasm"))),
        @('nurl_nw',       'NURL wasm (nwasm)',     $Nwasm,    ($NwasmArgs + @("$base.nu.wasm"))))
    if ($NwasmAllLangs) {
        $plan += ,@('c_nw',    'C wasm (nwasm)',    $Nwasm, ($NwasmArgs + @("$base.c.wasm")))
        $plan += ,@('rust_nw', 'Rust wasm (nwasm)', $Nwasm, ($NwasmArgs + @("$base.rs.wasm")))
    } else {
        $row.ms_c_nw = 'SKIPPED'; $row.reps_c_nw = 0
        $row.ms_rust_nw = 'SKIPPED'; $row.reps_rust_nw = 0
    }
    foreach ($p in $plan) {
        Progress-Line $b "timing $($p[1])…"
        $t = Time-Cell $p[2] $p[3]
        $row["ms_$($p[0])"] = $t.Ms; $row["reps_$($p[0])"] = $t.Reps
    }
    Write-Host ("`r`e[K  {0,-18} native {1,8}  jit {2,8}  nwasm {3,10}   (nurl)" -f `
        $b, $row.ms_nurl, $row.ms_nurl_ref, $row.ms_nurl_nw)
    $rows += $row
}
Write-Host "`r`e[K" -NoNewline

# ── emit ─────────────────────────────────────────────────────────
$Now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
function JStr([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '\\', '\\\\' -replace '"', '\"')
}
function JNum($v) {
    $s = [string]$v
    if ($s -match '^[0-9.]+$') { return $s }
    return 'null'
}
function IsNum($v) { return ([string]$v -match '^[0-9.]+$') }
# wasm ÷ native, one decimal, or an em dash when either end is missing.
function Ratio($a, $b) {
    if ((IsNum $a) -and (IsNum $b) -and [double]$b -gt 0) { return ('{0:F1}' -f ([double]$a / [double]$b)) }
    return '—'
}
# The same with each column's floor subtracted; refuses when a floor is more
# than half of its cell (wasmbench.sh explains why).
function RatioNet($a, $af, $b, $bf) {
    if (-not ((IsNum $a) -and (IsNum $af) -and (IsNum $b) -and (IsNum $bf))) { return '—' }
    $an = [double]$a - [double]$af; $bn = [double]$b - [double]$bf
    if ($an -le 0 -or $bn -le 0) { return '—' }
    if ($an -lt [double]$a / 2 -or $bn -lt [double]$b / 2) { return '—' }
    return ('{0:F1}' -f ($an / $bn))
}
function Kib($bytes) {
    if ([double]$bytes -gt 0) { return ('{0:F0}' -f ([double]$bytes / 1024)) }
    return '—'
}
function Pct($a, $b) {
    if (-not ((IsNum $a) -and (IsNum $b)) -or [double]$a -le 0) { return '—' }
    $d = ([double]$b - [double]$a) * 100 / [double]$a
    $sign = if ($d -gt 0) { '+' } elseif ($d -lt 0) { '−' } else { '' }
    return ('{0}{1:F0} %' -f $sign, [Math]::Abs($d))
}
# Table cells with every cell that ties for the fastest in bold.
function Row-FastestBold([string]$wrap, [object[]]$cells) {
    $min = $null
    foreach ($c in $cells) { if ((IsNum $c) -and ($null -eq $min -or [double]$c -lt $min)) { $min = [double]$c } }
    $s = ''
    foreach ($c in $cells) {
        $t = [string]$c
        if ($null -ne $min -and (IsNum $c) -and [double]$c -eq $min) { $t = "**$t**" }
        $s += " $wrap$t$wrap |"
    }
    return $s
}
function Wins([string]$key, [string]$refKey) {
    $won = 0; $both = 0
    foreach ($r in $rows) {
        if ((IsNum $r["ms_$key"]) -and (IsNum $r["ms_$refKey"])) {
            $both++
            if ([double]$r["ms_$key"] -lt [double]$r["ms_$refKey"]) { $won++ }
        }
    }
    if ($both -gt 0) { return "$won of $both" }
    return '—'
}

function Emit-Json {
    $sb = [System.Text.StringBuilder]::new()
    $w  = { param($t) [void]$sb.Append($t); [void]$sb.Append("`n") }
    & $w '{'
    & $w '  "schema": 1,'
    & $w '  "kind": "wasm",'
    & $w "  ""workload_scale"": $Scale,"
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
    & $w "    ""clang"": ""$(JStr $ClangVersion)"","
    & $w "    ""rustc"": ""$(JStr $RustcVersion)"","
    & $w "    ""zig"": ""$(JStr $ZigVersion)"","
    & $w "    ""wasmbuilder"": ""$(JStr $WasmbuilderVersion)"","
    & $w "    ""wasm_runtime_ref"": ""$(JStr $WasmtimeVersion)"","
    & $w "    ""wasm_runtime_nurl"": ""$(JStr $NwasmVersion)"""
    & $w '  },'
    & $w '  "settings": {'
    & $w "    ""opt"": ""$(JStr $Opt)"","
    & $w "    ""wasm_target_c"": ""$WasmTargetC"","
    & $w "    ""wasm_target_rust"": ""$WasmTargetRs"","
    & $w "    ""max_reps"": $MaxReps,"
    & $w "    ""budget_ms"": $BudgetMs,"
    & $w "    ""timeout_s"": $TimeoutS,"
    & $w "    ""compile_reps"": $CompileReps,"
    & $w "    ""interpreter_all_languages"": $(if ($NwasmAllLangs) { 'true' } else { 'false' })"
    & $w '  },'
    & $w '  "floor_ms": {'
    & $w ("    ""native"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2} }}," -f (JNum $fl.nurl), (JNum $fl.c), (JNum $fl.rust))
    & $w ("    ""wasm_ref"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2}, ""nurl_no_gc_sections"": {3} }}," -f `
        (JNum $fl.nurl_ref), (JNum $fl.c_ref), (JNum $fl.rust_ref), (JNum $fl.nurl_ref_nogc))
    & $w ("    ""wasm_nwasm"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2} }}" -f (JNum $fl.nurl_nw), (JNum $fl.c_nw), (JNum $fl.rust_nw))
    & $w '  },'
    & $w ("  ""floor_compile_ms"": {{ ""nurl_frontend"": {0}, ""nurl_native"": {1}, ""nurl_wasm"": {2}, ""nurl_wasm_no_gc_sections"": {3}, ""c_native"": {4}, ""c_wasm"": {5}, ""rust_native"": {6}, ""rust_wasm"": {7} }}," -f `
        (JNum $fl.cc_nurl_fe), (JNum $fl.cc_nurl), (JNum $fl.cc_nurl_wasm), (JNum $fl.cc_nurl_wasm_nogc),
        (JNum $fl.cc_c), (JNum $fl.cc_c_wasm), (JNum $fl.cc_rust), (JNum $fl.cc_rust_wasm))
    & $w '  "benchmarks": ['
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        & $w '    {'
        & $w "      ""name"": ""$(JStr $r.name)"","
        & $w "      ""blurb"": ""$(JStr $r.blurb)"","
        & $w "      ""measures"": ""$(JStr $r.measures)"","
        & $w "      ""checksum"": ""$(JStr $r.checksum)"","
        & $w "      ""verified"": $(if ($r.verified) { 'true' } else { 'false' }),"
        foreach ($sec in @(@('run_ms', 'ms_', $true), @('reps', 'reps_', $false))) {
            $p = $sec[1]
            $f = if ($sec[2]) { { param($v) JNum $v } } else { { param($v) [string]$v } }
            & $w "      ""$($sec[0])"": {"
            & $w ("        ""native"":   {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2} }}," -f `
                (& $f $r["${p}nurl"]), (& $f $r["${p}c"]), (& $f $r["${p}rust"]))
            & $w ("        ""wasm_ref"": {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2}, ""nurl_no_gc_sections"": {3} }}," -f `
                (& $f $r["${p}nurl_ref"]), (& $f $r["${p}c_ref"]), (& $f $r["${p}rust_ref"]), (& $f $r["${p}nurl_ref_nogc"]))
            & $w ("        ""wasm_nwasm"":  {{ ""nurl"": {0}, ""c"": {1}, ""rust"": {2} }}" -f `
                (& $f $r["${p}nurl_nw"]), (& $f $r["${p}c_nw"]), (& $f $r["${p}rust_nw"]))
            & $w '      },'
        }
        & $w ("      ""compile_ms"": {{ ""nurl_frontend"": {0}, ""nurl_native"": {1}, ""nurl_wasm"": {2}, ""nurl_wasm_no_gc_sections"": {3}, ""c_native"": {4}, ""c_wasm"": {5}, ""rust_native"": {6}, ""rust_wasm"": {7} }}," -f `
            (JNum $r.cc_nurl_fe), (JNum $r.cc_nurl), (JNum $r.cc_nurl_wasm), (JNum $r.cc_nurl_wasm_nogc),
            (JNum $r.cc_c), (JNum $r.cc_c_wasm), (JNum $r.cc_rust), (JNum $r.cc_rust_wasm))
        & $w ("      ""bytes"": {{ ""nurl_native"": {0}, ""nurl_wasm"": {1}, ""nurl_wasm_no_gc_sections"": {2}, ""c_native"": {3}, ""c_wasm"": {4}, ""rust_native"": {5}, ""rust_wasm"": {6} }}" -f `
            $r.sz_nurl, $r.sz_nurl_wasm, $r.sz_nurl_wasm_nogc, $r.sz_c, $r.sz_c_wasm, $r.sz_rust, $r.sz_rust_wasm)
        & $w ('    }' + $(if ($i -lt $rows.Count - 1) { ',' } else { '' }))
    }
    & $w '  ]'
    & $w '}'
    return $sb.ToString()
}

function Emit-Md {
    $L = [System.Collections.Generic.List[string]]::new()
    $a = { param($t) $L.Add($t) }

    & $a '# WebAssembly benchmark results (Windows) — NURL native vs NURL wasm'
    & $a ''
    & $a "Generated ``$Now`` by ``bench/wasmbench.ps1``, the Windows port of"
    & $a '`bench/wasmbench.sh`. **Do not edit by hand** — the next run overwrites it.'
    & $a "The machine-readable form of this same run is ``$(Split-Path -Leaf $Json)``."
    & $a ''
    if ($ScaleN -ne 1) {
        & $a "**Workload ×$Scale.** Every benchmark below does $Scale times its published"
        & $a 'work (`BENCH_SCALE` in each source, multiplied before compilation), so'
        & $a 'process start-up and module compilation are amortised and the generated'
        & $a 'code is what the cells measure.'
        & $a ''
    }
    & $a 'These are **not** the published numbers: those come from the Linux CI run'
    & $a 'in [`WASMRESULTS.md`](WASMRESULTS.md). The native NURL column links the way'
    & $a '`nurl.bat` does on this platform (no `-flto`, `-lwinhttp`), as in'
    & $a '`RESULTS-WINDOWS.md`; the wasm columns are the same modules on any host.'
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
    & $a ''
    & $a '| Component | Value |'
    & $a '|---|---|'
    & $a "| NURL → wasm | ``packages/wasmbuilder`` ($WasmbuilderVersion), built from this repo |"
    & $a "| C → wasm | ``$ZigVersion cc --target=$WasmTargetC`` |"
    & $a "| Rust → wasm | ``rustc --target $WasmTargetRs`` |"
    & $a "| wasm runtime (reference) | ``$WasmtimeVersion`` — Cranelift JIT |"
    & $a "| wasm runtime (NURL) | ``packages/nwasm`` ($NwasmVersion), built from this repo, ``NURL_SPLIT=0`` |"
    & $a ''
    & $a '| Setting | Value |'
    & $a '|---|---|'
    & $a "| Optimisation | NURL/C ``$Opt``, Rust ``-C opt-level=2``, both targets |"
    & $a "| Workload scale | ×$Scale |"
    & $a "| Timed runs per cell | up to $MaxReps, adaptive: as many as fit in $BudgetMs ms |"
    & $a "| Timed compiles per cell | $CompileReps (median) |"
    & $a "| Per-run timeout | $TimeoutS s |"
    & $a "| C/Rust on the NURL interpreter | $(if ($NwasmAllLangs) { 'yes' } else { 'no (add -NwasmAllLangs)' }) |"
    & $a '| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |'
    & $a ''

    & $a '## 1. What wasm costs — native vs the same module on a JIT'
    & $a ''
    & $a 'Whole-process wall clock in milliseconds, start-up included. The `x`'
    & $a 'columns are wasm ÷ native for that language.'
    & $a ''
    & $a '| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |'
    & $a '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|'
    & $a ("| _(floor: empty program)_ | _{0}_ | _{1}_ | _{2}_ | _{3}_ | _{4}_ | _{5}_ | _{6}_ | _{7}_ | _{8}_ |" -f `
        $fl.nurl, $fl.nurl_ref, (Ratio $fl.nurl_ref $fl.nurl), $fl.c, $fl.c_ref, (Ratio $fl.c_ref $fl.c),
        $fl.rust, $fl.rust_ref, (Ratio $fl.rust_ref $fl.rust))
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $r.name,
            $r.ms_nurl, $r.ms_nurl_ref, (Ratio $r.ms_nurl_ref $r.ms_nurl),
            $r.ms_c, $r.ms_c_ref, (Ratio $r.ms_c_ref $r.ms_c),
            $r.ms_rust, $r.ms_rust_ref, (Ratio $r.ms_rust_ref $r.ms_rust))
    }
    & $a ''

    & $a '## 2. The same ratios, with start-up subtracted'
    & $a ''
    & $a 'Cell minus the floor of its own column, wasm ÷ native. A `—` means the'
    & $a 'floor is more than half of that cell, so no signal is left after the'
    & $a 'subtraction.'
    & $a ''
    & $a '| Benchmark | NURL x | NURL no-gc x | C x | Rust x |'
    & $a '|---|---:|---:|---:|---:|'
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} |" -f $r.name,
            (RatioNet $r.ms_nurl_ref $fl.nurl_ref $r.ms_nurl $fl.nurl),
            (RatioNet $r.ms_nurl_ref_nogc $fl.nurl_ref_nogc $r.ms_nurl $fl.nurl),
            (RatioNet $r.ms_c_ref $fl.c_ref $r.ms_c $fl.c),
            (RatioNet $r.ms_rust_ref $fl.rust_ref $r.ms_rust $fl.rust))
    }
    & $a ''

    & $a '## 3. The pure-NURL runtime (`packages/nwasm`)'
    & $a ''
    & $a 'The identical modules, on the reference runtime and on `nwasm`. The'
    & $a 'fastest of the six cells in a row is in **bold**.'
    & $a ''
    & $a '| Benchmark | NURL on `wasmtime` | NURL on `nwasm` | C on `wasmtime` | C on `nwasm` | Rust on `wasmtime` | Rust on `nwasm` |'
    & $a '|---|---:|---:|---:|---:|---:|---:|'
    & $a ('| _(floor: empty program)_ |' + (Row-FastestBold '_' @($fl.nurl_ref, $fl.nurl_nw, $fl.c_ref, $fl.c_nw, $fl.rust_ref, $fl.rust_nw)))
    foreach ($r in $rows) {
        & $a (("| ``{0}`` |" -f $r.name) + (Row-FastestBold '' @($r.ms_nurl_ref, $r.ms_nurl_nw, $r.ms_c_ref, $r.ms_c_nw, $r.ms_rust_ref, $r.ms_rust_nw)))
    }
    & $a ''
    $wNu = Wins 'nurl_nw' 'nurl_ref'; $wC = Wins 'c_nw' 'c_ref'; $wRs = Wins 'rust_nw' 'rust_ref'
    if ($wC -eq '—' -and $wRs -eq '—') {
        & $a "``nwasm`` is faster than the reference runtime on $wNu NURL modules (the C and Rust modules were not run on ``nwasm`` this time)."
    } else {
        & $a "``nwasm`` is faster than the reference runtime on $wNu NURL modules, $wC C modules and $wRs Rust modules."
    }
    & $a ''
    & $a '| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |'
    & $a '|---|---:|---:|---:|---:|---:|'
    & $a ("| _(floor: empty program)_ | _{0}_ | _{1}_ | _{2}_ | _{3}_ | _{4}_ |" -f $fl.nurl_nw,
        (Ratio $fl.nurl_nw $fl.nurl_ref), (Ratio $fl.nurl_nw $fl.nurl), (Ratio $fl.c_nw $fl.c_ref), (Ratio $fl.rust_nw $fl.rust_ref))
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} |" -f $r.name, $r.ms_nurl_nw,
            (Ratio $r.ms_nurl_nw $r.ms_nurl_ref), (Ratio $r.ms_nurl_nw $r.ms_nurl),
            (Ratio $r.ms_c_nw $r.ms_c_ref), (Ratio $r.ms_rust_nw $r.ms_rust_ref))
    }
    & $a ''

    & $a '## 4. Artefact size (KiB)'
    & $a ''
    & $a '| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |'
    & $a '|---|---:|---:|---:|---:|---:|---:|'
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} | {6} |" -f $r.name,
            (Kib $r.sz_nurl), (Kib $r.sz_nurl_wasm), (Kib $r.sz_c), (Kib $r.sz_c_wasm), (Kib $r.sz_rust), (Kib $r.sz_rust_wasm))
    }
    & $a ''

    & $a '## 5. Dead code — what `--no-gc-sections` would cost'
    & $a ''
    & $a '| Benchmark | Size | Size no-gc | Δ | JIT | JIT no-gc | Δ |'
    & $a '|---|---:|---:|---:|---:|---:|---:|'
    & $a ("| _(floor: empty program)_ | _{0}_ | _{1}_ | _{2}_ | _{3}_ | _{4}_ | _{5}_ |" -f `
        (Kib $fl.sz_nurl_wasm), (Kib $fl.sz_nurl_wasm_nogc), (Pct $fl.sz_nurl_wasm $fl.sz_nurl_wasm_nogc),
        $fl.nurl_ref, $fl.nurl_ref_nogc, (Pct $fl.nurl_ref $fl.nurl_ref_nogc))
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} | {6} |" -f $r.name,
            (Kib $r.sz_nurl_wasm), (Kib $r.sz_nurl_wasm_nogc), (Pct $r.sz_nurl_wasm $r.sz_nurl_wasm_nogc),
            $r.ms_nurl_ref, $r.ms_nurl_ref_nogc, (Pct $r.ms_nurl_ref $r.ms_nurl_ref_nogc))
    }
    & $a ''

    & $a '## 6. Compile time (median, ms)'
    & $a ''
    & $a '| Benchmark | NURL `nurlc` | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |'
    & $a '|---|---:|---:|---:|---:|---:|---:|---:|'
    & $a ("| _(floor: empty program)_ | _{0}_ | _{1}_ | _{2}_ | _{3}_ | _{4}_ | _{5}_ | _{6}_ |" -f `
        $fl.cc_nurl_fe, $fl.cc_nurl, $fl.cc_nurl_wasm, $fl.cc_c, $fl.cc_c_wasm, $fl.cc_rust, $fl.cc_rust_wasm)
    foreach ($r in $rows) {
        & $a ("| ``{0}`` | {1} | {2} | {3} | {4} | {5} | {6} | {7} |" -f $r.name,
            $r.cc_nurl_fe, $r.cc_nurl, $r.cc_nurl_wasm, $r.cc_c, $r.cc_c_wasm, $r.cc_rust, $r.cc_rust_wasm)
    }
    & $a ''

    & $a '## 7. Correctness gate'
    & $a ''
    & $a 'Each row is timed only when every cell prints the same line as the native'
    & $a 'NURL binary (CRLF normalised to LF). The interpreter is inside the gate.'
    & $a ''
    & $a '| Benchmark | Output | Verdict |'
    & $a '|---|---|---|'
    $interp = if ($NwasmAllLangs) { ', interpreter' } else { ', interpreter (NURL only)' }
    foreach ($r in $rows) {
        if ($r.verified) {
            & $a ("| ``{0}`` | ``{1}`` | identical: 3 languages x {{native, JIT{2}}}, + NURL wasm ``--no-gc-sections`` |" -f $r.name, $r.checksum, $interp)
        } else {
            & $a ("| ``{0}`` | — | **MISMATCH** — {1} |" -f $r.name, $r.detail)
        }
    }
    & $a ''
    & $a '## 8. Reading the numbers'
    & $a ''
    & $a '* See [`WASMRESULTS.md`](WASMRESULTS.md) section 8: floors, the disabled'
    & $a '  module cache, the `--dir .` preopen and run-to-run drift read the same'
    & $a '  way here.'
    & $a '* The crypto rows (`chacha20`, `poly1305`, `blake2b`, `sha512`, `x25519`)'
    & $a '  run the NURL standard library''s own implementations in the NURL column;'
    & $a '  C and Rust carry the same formulation written out by hand.'

    return (($L -join "`n") + "`n")
}

if ($Stdout) {
    Write-Output (Emit-Md)
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Json), (Split-Path -Parent $Md) | Out-Null
    [System.IO.File]::WriteAllText($Json, (Emit-Json), $Utf8NoBom)
    [System.IO.File]::WriteAllText($Md,   (Emit-Md),   $Utf8NoBom)
    Write-Host "wrote $Json"
    Write-Host "wrote $Md"
}

foreach ($r in $rows) {
    if (-not $r.verified) {
        Write-Host 'wasmbench.ps1: at least one row failed the correctness gate' -ForegroundColor Red
        exit 1
    }
}
exit 0
