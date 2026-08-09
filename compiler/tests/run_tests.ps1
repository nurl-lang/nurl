#!/usr/bin/env pwsh
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
# ============================================================
#  run_tests.ps1 — Windows compiler test runner with PER-TEST
#  golden files. Faithful port of run_tests.sh.
#
#  For every <name>.nu in this directory the runner produces an
#  "actual record" describing the outcome, and compares it
#  byte-for-byte against the golden file
#  compiler/tests/outputs-windows/<name>.txt.
#
#  Why a SEPARATE golden directory (outputs-windows/, not outputs/):
#  Windows records legitimately differ from the Linux/macOS ones —
#  argv[0] is ".\name.exe" not "./name", a handful of FFI-backed
#  tests skip (build.bat builds runtime.o without the libcurl/
#  openssl/sqlite/… feature sentinels), and exit codes for crashes
#  differ. Keeping the two golden sets apart means a Windows drift
#  never masquerades as a Linux regression and vice-versa.
#
#  Record shapes (the golden holds exactly these lines):
#
#    normal test          should_fail_* / borrow_* / arity_strict_* / lint_*
#    ───────────          ────────────────────────
#    COMPILE OK           COMPILE FAIL
#    LINK OK              ERRORS              (borrow_* only, if any)
#    EXIT <n>             <diagnostics>
#    OUTPUT
#    <stdout+stderr>
#
#    should_warn_* additionally carry a WARNINGS block between
#    COMPILE OK and LINK OK.
#
#  Regression safety net (kept in exact bijection with the test set):
#    * a non-skipped test whose golden is MISSING fails the run.
#    * a golden with no matching .nu (ORPHAN) fails the run.
#
#  Usage:
#    pwsh run_tests.ps1                 # check against goldens (CI)
#    pwsh run_tests.ps1 -Update         # (re)write all goldens
#    pwsh run_tests.ps1 -Update a b …   # update only the named tests
#
#  Which tests run: the same `// requires:` declaration the POSIX
#  runners read (see test_skips.sh for the contract and for why the
#  name lists that used to live here were wrong). Tokens: `live`,
#  `internet`, or the name of a tool that must be on PATH.
#
#  ONE difference from the POSIX side, and it is a capability fact
#  rather than a policy: `fibers` is OFF here. NURL has no Win64
#  context-switch backend (docs/ASYNC.md), so `spawn` returns a null
#  handle and the closure never runs — a test that pairs a fiber-side
#  server with a blocking client would wait forever for a peer that
#  cannot exist. `live` is ON, same as everywhere else: Windows has
#  threads and sockets, and udp_basic / websocket_basic / net_basic
#  have been exercising them here all along.
#
#  Environment (mirrors run_tests.sh):
#    NURL_TEST_JOBS=N   parallelism (default: CPU count)
#    NURL_LIVE_TESTS=0  turn off the live (threads/sockets) tests
#    NURL_FIBER_TESTS=1 force the fiber tests on (see above)
#    NURL_HTTP_TESTS=1  opt in to the tests that contact a third party
#    NURL_NET_TESTS=1   same as NURL_HTTP_TESTS (both spellings exist)
#    TIMEOUT=N          per-test run timeout, seconds (default 60)
#    MAX_OUT_LINES=N    cap captured output lines (default 200)
#    CLANG=path         override clang
#
#  Exit code: 0 iff every test matches its golden, no failures, no
#  missing goldens and no orphans. 1 otherwise. 2 on setup error.
# ============================================================
[CmdletBinding()]
param(
    [switch]$Update,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Only
)
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
# Imports inside tests are spelled repo-root-relative; nurlc resolves
# them against the CWD, so anchor every spawned process there.
Set-Location $RootDir

$Nurlc   = Join-Path $RootDir 'build\nurlc.exe'
$Runtime = Join-Path $RootDir 'stdlib\runtime.o'
$OutDir  = Join-Path $ScriptDir 'outputs-windows'
$WorkDir = Join-Path $RootDir 'build\tests'

if (-not (Test-Path $Nurlc)) {
    Write-Error "nurlc not found at $Nurlc — run build.bat"; exit 2
}
if (-not (Test-Path $Runtime)) {
    Write-Error "runtime.o not found at $Runtime"; exit 2
}
if ($env:NURL_SAN -eq '1') {
    Write-Error "NURL_SAN=1 — sanitized runs are a Linux/macOS path (run_san_tests.sh)."; exit 2
}

# ── Locate clang (PATH, then the usual LLVM install dirs) ────────
$Clang = if ($env:CLANG) { $env:CLANG } else { 'clang' }
if (-not (Get-Command $Clang -ErrorAction SilentlyContinue) -and -not (Test-Path $Clang)) {
    foreach ($c in @("$env:ProgramFiles\LLVM\bin\clang.exe",
                     "${env:ProgramFiles(x86)}\LLVM\bin\clang.exe")) {
        if (Test-Path $c) { $Clang = $c; break }
    }
}
if (-not (Get-Command $Clang -ErrorAction SilentlyContinue) -and -not (Test-Path $Clang)) {
    Write-Error "clang not found"; exit 2
}

# build.bat compiles runtime.o WITHOUT -flto and links winhttp only, so
# no -flto here and no pkg-config feature libs — match that link line.
$LinkLibs    = '-lwinhttp'
# Feature libs build.bat detected (zlib/zstd → stdlib\runtime.winlibs), so
# tests importing stdlib\ext\compress.nu link the same way nurl.bat does
# (mirrors run_tests.sh's pkg-config LINK_LIBS). Parse into clean argv
# tokens: -L<dir> (quotes stripped; ArgumentList re-quotes if it has spaces)
# and -l<name>. Empty when no vcpkg zlib/zstd, leaving those tests to skip.
$WinLibs = @()
$winFile = Join-Path $RootDir 'stdlib\runtime.winlibs'
if (Test-Path $winFile) {
    $winRaw = [System.IO.File]::ReadAllText($winFile)
    foreach ($m in [regex]::Matches($winRaw, '-L"([^"]*)"|-L(\S+)|-l(\S+)')) {
        if     ($m.Groups[1].Success) { $WinLibs += ('-L' + $m.Groups[1].Value) }
        elseif ($m.Groups[2].Success) { $WinLibs += ('-L' + $m.Groups[2].Value) }
        else                          { $WinLibs += ('-l' + $m.Groups[3].Value) }
    }
}
$MaxOutLines = if ($env:MAX_OUT_LINES) { [int]$env:MAX_OUT_LINES } else { 200 }
$Timeout     = if ($env:TIMEOUT)       { [int]$env:TIMEOUT }       else { 60 }
$Jobs        = if ($env:NURL_TEST_JOBS){ [int]$env:NURL_TEST_JOBS} else { [Environment]::ProcessorCount }
$EnableLive     = if ($env:NURL_LIVE_TESTS) { $env:NURL_LIVE_TESTS } else { '1' }
# See the header: no Win64 context-switch backend, so this one differs
# from the POSIX default on purpose.
$EnableFibers   = if ($env:NURL_FIBER_TESTS) { $env:NURL_FIBER_TESTS } else { '0' }
$EnableInternet = if (($env:NURL_HTTP_TESTS -eq '1') -or ($env:NURL_NET_TESTS -eq '1')) { '1' } else { '0' }

New-Item -ItemType Directory -Force -Path $OutDir, $WorkDir | Out-Null

# ── collect the test set (ordinal sort, LC_ALL=C equivalent) ─────
$names = @(Get-ChildItem -Path $ScriptDir -Filter '*.nu' -File | ForEach-Object { $_.BaseName })
if ($names.Count -eq 0) { Write-Error "no .nu files in $ScriptDir"; exit 2 }
[Array]::Sort($names, [System.StringComparer]::Ordinal)
if ($Only) { $names = $Only }

$updateFlag = [bool]$Update

# ── run in parallel ─────────────────────────────────────────────
# Each worker is self-contained: it compiles, links, runs, then
# compares/updates its own golden and returns a verdict object.
# Writing distinct golden files from parallel threads is race-free.
$results = $names | ForEach-Object -ThrottleLimit $Jobs -Parallel {
    $name        = $_
    $ScriptDir   = $using:ScriptDir
    $RootDir     = $using:RootDir
    $OutDir      = $using:OutDir
    $WorkDir     = $using:WorkDir
    $Nurlc       = $using:Nurlc
    $Runtime     = $using:Runtime
    $Clang       = $using:Clang
    $WinLibs     = $using:WinLibs
    $MaxOutLines = $using:MaxOutLines
    $Timeout     = $using:Timeout
    $Update      = $using:updateFlag
    $EnableLive     = $using:EnableLive
    $EnableFibers   = $using:EnableFibers
    $EnableInternet = $using:EnableInternet

    function Read-TextOrEmpty([string]$p) {
        if (-not (Test-Path -LiteralPath $p)) { return '' }
        # Start-Process can hold the redirected output handle for a beat
        # after the child exits — retry past the transient lock.
        for ($i = 0; $i -lt 100; $i++) {
            try { return [System.IO.File]::ReadAllText($p) }
            catch [System.IO.IOException] { Start-Sleep -Milliseconds 20 }
        }
        return [System.IO.File]::ReadAllText($p)
    }
    # Run a process to completion, capturing stdout/stderr IN MEMORY (no
    # temp files → no redirect-handle locking). Used for nurlc and clang
    # where argv[0] is irrelevant. Async reads avoid pipe-buffer deadlock.
    function Run-Proc([string]$exe, [string[]]$argList, [string]$cwd) {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe
        foreach ($a in $argList) { [void]$psi.ArgumentList.Add($a) }
        $psi.WorkingDirectory       = $cwd
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $o = $proc.StandardOutput.ReadToEndAsync()
        $e = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        return @{ Code = $proc.ExitCode; Out = $o.Result; Err = $e.Result }
    }
    function Normalize([string]$s) {
        if ($null -eq $s) { return '' }
        return ($s -replace "`r`n", "`n" -replace "`r", "`n")
    }
    # Strip the absolute repo-root prefix so records are checkout-portable.
    function Strip-Root([string]$s) {
        $s = $s -replace [regex]::Escape($RootDir + '\'), ''
        $s = $s -replace [regex]::Escape($RootDir + '/'), ''
        # clang/lld scratch objects carry a per-run random hash, e.g.
        #   C:\Users\…\Temp\term_basic-fcee18.o  →  term_basic.o
        # which would make a LINK FAIL golden non-deterministic. Collapse
        # the temp-dir prefix and the -<hash> suffix to a stable form.
        $s = $s -replace '(?i)[A-Za-z]:\\[^\r\n:]*\\([A-Za-z0-9_.]+)-[0-9a-f]{6,}\.o', '$1.o'
        return $s
    }
    # Append text, capping to MaxOutLines newline-terminated lines.
    function Cap-Lines([string]$text) {
        $nl = ([regex]::Matches($text, "`n")).Count
        if ($nl -le $MaxOutLines) { return $text }
        $lines = $text -split "`n", -1
        $kept  = $lines[0..($MaxOutLines - 1)] -join "`n"
        $rest  = $nl - $MaxOutLines
        return ($kept + "`n[... $rest more lines truncated ...]`n")
    }
    # Run a native exe to completion, with timeout, capturing combined
    # stdout+stderr in memory and the exit code (124 on timeout, matching
    # `timeout`). Full-path FileName + WorkingDirectory: argv[0] is the
    # absolute path, which Strip-Root rewrites to a repo-relative form.
    function Invoke-WithTimeout([string]$exe, [string]$cwd, [int]$secs) {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName               = $exe
        $psi.WorkingDirectory       = $cwd
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        # Windows auto-flags exes whose name contains "install"/"setup"/etc.
        # as requiring UAC elevation (installer-detection heuristic), which
        # makes Process.Start throw for e.g. pkg_install_e2e.exe. RunAsInvoker
        # suppresses that so the test runs unprivileged like on Linux.
        $psi.Environment['__COMPAT_LAYER'] = 'RunAsInvoker'
        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
        } catch {
            # Couldn't even launch (e.g. still blocked by policy). Record it
            # as a run failure instead of crashing the whole worker.
            return @{ Code = -1; Out = "run failed: $($_.Exception.Message)`n" }
        }
        $o = $proc.StandardOutput.ReadToEndAsync()
        $e = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($secs * 1000)) {
            try { $proc.Kill($true) } catch {}
            try { $proc.WaitForExit() } catch {}
            $code = 124
        } else {
            $code = $proc.ExitCode
        }
        return @{ Code = $code; Out = ($o.Result + $e.Result) }
    }

    # ── per-test scratch paths ──────────────────────────────────
    $src  = "compiler/tests/$name.nu"     # repo-relative → portable diagnostics
    $ll   = Join-Path $WorkDir "$name.ll"
    $bin  = Join-Path $WorkDir "$name.exe"
    $err  = Join-Path $WorkDir "$name.err"
    $gold = Join-Path $OutDir  "$name.txt"
    foreach ($f in @($ll, $bin, $err)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

    # Echo a test's declared requirement tokens (test_skips.sh's
    # test_requires, in PowerShell). Leading comment block only: the
    # block ends at the first line that is neither a comment nor blank,
    # which is the real boundary — a fixed line window would stop seeing
    # the declaration of any test that grew a longer header, and losing
    # a declaration means the test runs where it cannot.
    function Get-Requires([string]$path) {
        if (-not (Test-Path -LiteralPath $path)) { return @() }
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ($line -match '^\s*$')   { continue }
            if ($line -match '^\s*//') {
                if ($line -match '^\s*//\s*requires:\s*(.+)$') {
                    return ($Matches[1] -split '\s+' | Where-Object { $_ })
                }
                continue
            }
            break
        }
        return @()
    }

    # ── is_skipped ──────────────────────────────────────────────
    $skip = $false
    if ($name -match '(_mod|_helper|_lib)$') { $skip = $true }
    # POSIX-only surfaces with no Windows equivalent: termios raw mode and
    # AF_UNIX socketpair. Their link errors are environment text (lld/MSVC
    # version-dependent), so golden-ing the failure is brittle — skip.
    elseif (@('term_basic','unixsock') -contains $name) { $skip = $true }
    # std/fswatch.nu is Linux-only (inotify is a Linux kernel API) — the
    # posix runner skips it everywhere but Linux, and so do we. Its old
    # Windows golden RECORDED the link failure, which is a blessed
    # breakage, not coverage.
    elseif ($name -like 'fswatch_*') { $skip = $true }
    # fs_glob_symlink builds a symlinked directory under /tmp and globs
    # through it. Windows has neither an unprivileged symlink() nor /tmp.
    # It first declared `requires: ln` as a capability probe, on the
    # reasoning that a host without `ln` is a host without symlinks —
    # which is false HERE specifically: this runner has Git for Windows
    # on PATH, so `ln.exe` resolves, the gate passed, and the test ran
    # and failed. A POSIX-only test belongs in this list, next to the
    # termios and AF_UNIX ones, not behind a command-presence guess.
    elseif ($name -eq 'fs_glob_symlink') { $skip = $true }
    else {
        foreach ($tok in (Get-Requires (Join-Path $ScriptDir "$name.nu"))) {
            switch ($tok) {
                'live'     { if ($EnableLive     -ne '1') { $skip = $true } }
                'fibers'   { if ($EnableFibers   -ne '1') { $skip = $true } }
                'internet' { if ($EnableInternet -ne '1') { $skip = $true } }
                # Anything else names an external command the test shells
                # out to. Absent tool → skip, so a stripped host degrades
                # to running less rather than failing on someone else's
                # missing package.
                default    { if (-not (Get-Command $tok -ErrorAction SilentlyContinue)) { $skip = $true } }
            }
            if ($skip) { break }
        }
    }
    if ($skip) { return [pscustomobject]@{ Name = $name; Verdict = 'SKIP'; Diff = '' } }

    # ── build the actual record ─────────────────────────────────
    $act = $null

    $enc0 = New-Object System.Text.UTF8Encoding $false

    if ($name -like 'borrow_*') {
        # borrow_* — violations are compile errors; the diagnostic is
        # baselined. borrow_strict_* only fire under the stricter flag.
        $nargs = @()
        if ($name -like 'borrow_strict_*') { $nargs += '--strict-borrowck' }
        $nargs += $src
        $r = Run-Proc $Nurlc $nargs $RootDir
        if ($r.Code -eq 0) {
            $act = "COMPILE OK`n(expected COMPILE FAIL but compiler accepted it)`n"
        } else {
            $act = "COMPILE FAIL`n"
            $e = Normalize $r.Err
            if ($e.Length -gt 0) { $act += "ERRORS`n" + (Cap-Lines (Strip-Root $e)) }
        }
    }
    elseif ($name -like 'lint_*') {
        # lint_* — diagnostics that only fire under --lint. Compiles
        # clean (the program is valid); it is the WARNINGS that are
        # baselined. Mirrors run_tests.sh.
        $r = Run-Proc $Nurlc @('--lint', $src) $RootDir
        if ($r.Code -eq 0) {
            $act = "COMPILE OK`n"
            $e = Normalize $r.Err
            if ($e.Length -gt 0) { $act += "WARNINGS`n" + (Cap-Lines (Strip-Root $e)) }
        } else {
            $act = "COMPILE FAIL`n(expected COMPILE OK)`n"
            $e = Normalize $r.Err
            if ($e.Length -gt 0) { $act += (Cap-Lines (Strip-Root $e)) }
        }
    }
    elseif ($name -like 'arity_strict_*') {
        # arity_strict_* — the n-ary '&'/'|' trap, an error only under
        # --strict-arity. The diagnostic TEXT is baselined because where
        # it points is the point. Mirrors run_tests.sh.
        $r = Run-Proc $Nurlc @('--strict-arity', $src) $RootDir
        if ($r.Code -eq 0) {
            $act = "COMPILE OK`n(expected COMPILE FAIL but compiler accepted it)`n"
        } else {
            $act = "COMPILE FAIL`n"
            $e = Normalize $r.Err
            if ($e.Length -gt 0) { $act += "ERRORS`n" + (Cap-Lines (Strip-Root $e)) }
        }
    }
    elseif ($name -like 'should_fail_*') {
        # should_fail_* — COMPILE FAIL is the expected outcome.
        $r = Run-Proc $Nurlc @($src) $RootDir
        if ($r.Code -eq 0) {
            $act = "COMPILE OK`n(expected COMPILE FAIL but compiler accepted it)`n"
        } else {
            $act = "COMPILE FAIL`n"
        }
    }
    elseif ($name -like 'diag_*') {
        # diag_* — like should_fail_ but the diagnostic TEXT is baselined
        # (default flags; front-end stderr captured verbatim).
        $r = Run-Proc $Nurlc @($src) $RootDir
        if ($r.Code -eq 0) {
            $act = "COMPILE OK`n(expected COMPILE FAIL but compiler accepted it)`n"
        } else {
            $act = "COMPILE FAIL`n"
            $e = Normalize $r.Err
            if ($e.Length -gt 0) { $act += "ERRORS`n" + (Cap-Lines (Strip-Root $e)) }
        }
    }
    else {
        $isWarn = $name -like 'should_warn_*'
        $r = Run-Proc $Nurlc @($src) $RootDir
        $cc  = $r.Code
        $cerr = Normalize $r.Err
        if ($cc -ne 0) {
            # nurlc refuses FFI decls whose external lib wasn't found at
            # build time. build.bat ships no feature sentinels, so this is
            # an environment gap, not a regression — skip (mirrors the .bat).
            if ($cerr -match 'no build-time sentinel') {
                return [pscustomobject]@{ Name = $name; Verdict = 'SKIP'; Diff = '' }
            }
            $act = "COMPILE FAIL`nERRORS`n" + (Cap-Lines (Strip-Root $cerr))
        } else {
            # IR must hit disk for clang to consume it.
            [System.IO.File]::WriteAllText($ll, $r.Out, $enc0)
            $linkArgs = @('-O2', $ll, $Runtime, '-lwinhttp') + $WinLibs + @('-o', $bin)
            $lr = Run-Proc $Clang $linkArgs $RootDir
            if ($lr.Code -ne 0) {
                # link.exe reports the unresolved SYMBOLS (LNK2019) on
                # STDOUT and clang only relays the exit code on stderr —
                # capture both, or every link failure reads "exit code
                # 1120" with the one fact that matters missing.
                $le = Normalize ($lr.Out + $lr.Err)
                $act = "COMPILE OK`nLINK FAIL`n" + (Cap-Lines (Strip-Root $le))
            } else {
                # Each test runs in its OWN scratch dir so relative-path
                # file side effects can't collide with a sibling. The exe
                # is invoked as ".\name.exe" so argv[0] stays stable.
                $rundir = Join-Path $WorkDir "run\$name"
                if (Test-Path -LiteralPath $rundir) { Remove-Item -LiteralPath $rundir -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $rundir | Out-Null
                $runExe = Join-Path $rundir "$name.exe"
                Copy-Item -LiteralPath $bin -Destination $runExe -Force
                $r = Invoke-WithTimeout $runExe $rundir $Timeout
                Remove-Item -LiteralPath $rundir -Recurse -Force -ErrorAction SilentlyContinue

                $act = "COMPILE OK`n"
                if ($isWarn -and $cerr.Length -gt 0) {
                    $act += "WARNINGS`n" + (Cap-Lines (Strip-Root $cerr))
                }
                # Strip the repo root from output too: the full-path launch
                # means argv[0] (and any path a program echoes) is absolute;
                # rewriting to repo-relative keeps goldens checkout-portable.
                $act += "LINK OK`nEXIT $($r.Code)`nOUTPUT`n" + (Cap-Lines (Strip-Root (Normalize $r.Out)))
            }
        }
    }

    # ── compare / update ────────────────────────────────────────
    # -Update always writes the WINDOWS golden — that part of the two-set
    # design stays. But for COMPARISON, a test with no Windows golden falls
    # back to the posix one: 500 of the 524 Windows goldens are byte-identical
    # to their posix twins, so requiring a hand-run `-Update` on a Windows box
    # for every new test bought nothing except a permanently lagging suite
    # (13 MISSING at v0.15.0). With the fallback, a new test is covered on
    # Windows from the day it lands; a test whose Windows behaviour GENUINELY
    # differs fails loudly against the posix golden — and that failure is the
    # deliberate moment to add an outputs-windows/ golden for it. Silent lag
    # becomes an actionable diff, and an existing Windows golden still always
    # wins, so a Windows drift can never masquerade as a Linux regression.
    $enc = New-Object System.Text.UTF8Encoding $false
    if ($Update) {
        [System.IO.File]::WriteAllText($gold, $act, $enc)
        return [pscustomobject]@{ Name = $name; Verdict = 'UPDATED'; Diff = '' }
    }
    if (-not (Test-Path -LiteralPath $gold)) {
        $posixGold = Join-Path (Join-Path $ScriptDir 'outputs') "$name.txt"
        if (Test-Path -LiteralPath $posixGold) { $gold = $posixGold }
    }
    if (-not (Test-Path -LiteralPath $gold)) {
        return [pscustomobject]@{ Name = $name; Verdict = 'MISSING'; Diff = '' }
    }
    $goldText = Normalize (Read-TextOrEmpty $gold)
    if ($goldText -ceq $act) {
        return [pscustomobject]@{ Name = $name; Verdict = 'PASS'; Diff = '' }
    }
    $cmp = Compare-Object ($goldText -split "`n") ($act -split "`n")
    $diff = ($cmp | ForEach-Object {
        $sign = if ($_.SideIndicator -eq '<=') { '-' } else { '+' }
        "$sign $($_.InputObject)"
    }) -join "`n"
    # Compare-Object matches line SETS, not sequences, so a pure
    # REORDERING fails the byte compare above and produces no rows here —
    # a FAIL printed under an empty diff, which reads like a harness bug.
    # Name the actual difference instead. (stdout_flush_order hit this:
    # the runner concatenates the child's two pipes rather than
    # interleaving them, so its lines arrive in a different order than
    # the posix golden records.)
    if ([string]::IsNullOrWhiteSpace($diff)) {
        $diff = '  (same lines, different order — golden and actual differ only in sequence)'
    }
    return [pscustomobject]@{ Name = $name; Verdict = 'FAIL'; Diff = $diff }
}

# ── aggregate ───────────────────────────────────────────────────
$pass = 0; $fail = 0; $missing = 0; $updated = 0; $skip = 0
$failed = @(); $missed = @()
foreach ($r in $results) {
    switch ($r.Verdict) {
        'PASS'    { $pass++ }
        'UPDATED' { $updated++ }
        'SKIP'    { $skip++ }
        'FAIL'    { $fail++;    $failed += $r }
        'MISSING' { $missing++; $missed += $r.Name }
    }
}

# ── orphan goldens (golden with no matching .nu) ────────────────
$orphans = @()
if (-not $Only) {
    foreach ($g in (Get-ChildItem -Path $OutDir -Filter '*.txt' -File -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath (Join-Path $ScriptDir "$($g.BaseName).nu"))) {
            $orphans += $g.BaseName
        }
    }
}

# ── report ──────────────────────────────────────────────────────
if ($Update) {
    Write-Host "Updated $updated golden(s); skipped $skip."
    if ($orphans.Count -gt 0) {
        Write-Host "NOTE: $($orphans.Count) orphan golden(s) remain (no .nu): $($orphans -join ' ')"
    }
    exit 0
}

$status = 0
if ($fail -gt 0) {
    Write-Host "=== $fail test(s) differ from their golden ==="
    foreach ($f in ($failed | Sort-Object Name)) {
        Write-Host ""
        Write-Host "--- $($f.Name) ---"
        Write-Host $f.Diff
    }
    $status = 1
}
if ($missing -gt 0) {
    Write-Host ""
    Write-Host "=== $missing test(s) have NO golden (run: run_tests.ps1 -Update $($missed -join ' ')) ==="
    $missed | Sort-Object | ForEach-Object { Write-Host "  $_" }
    $status = 1
}
if ($orphans.Count -gt 0) {
    Write-Host ""
    Write-Host "=== $($orphans.Count) orphan golden(s) — delete or add the .nu ==="
    $orphans | Sort-Object | ForEach-Object { Write-Host "  $_" }
    $status = 1
}

Write-Host ""
Write-Host "PASS $pass · FAIL $fail · MISSING $missing · ORPHAN $($orphans.Count) · SKIP $skip  (jobs=$Jobs)"
if ($status -eq 0) { Write-Host "TESTS PASSED" } else { Write-Host "TESTS FAILED" }
exit $status
