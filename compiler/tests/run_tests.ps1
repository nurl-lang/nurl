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
#  `fibers`, `internet`, the CPU tiers, or the name of a tool that must
#  be on PATH — with the same defaults as there: `live` and `fibers` ON
#  (the fiber runtime runs on Win64's own context switch, docs/ASYNC.md).
#
#  The differences from the POSIX side are capability facts, not policy:
#  `ktls` is never met here (a Linux kernel facility), and the
#  CPU tiers are answered by the runtime's own CPUID gates — Windows has
#  no /proc/cpuinfo, so the runner links a probe against runtime.o and
#  asks nurl_cpu_x86_*, NURL_CPU_* overrides included.
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

# ── UTF-8 end to end ────────────────────────────────────────────
# nurlc's diagnostics, the test programs' output and the goldens are all
# UTF-8. .NET decodes a redirected child pipe with Console.OutputEncoding,
# which on a stock Windows console is the OEM code page (850 on a fi-FI box,
# 437 on en-US) — so '—', '→' and 'ä' arrive mojibake'd, get compared against
# a correct UTF-8 golden, and the test "differs" for an encoding reason alone.
# That is one bug with two halves: pin this console to UTF-8 here so the
# report and its diff print honestly, and pin every redirected stream below
# so the records are built from the bytes the child actually wrote.
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
try {
    [Console]::OutputEncoding = $Utf8NoBom
    $OutputEncoding           = $Utf8NoBom
} catch {
    # No console attached (fully redirected CI job). The per-stream
    # encodings are what carry the fix; this half is cosmetic.
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir   = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
# Imports inside tests are spelled repo-root-relative; nurlc resolves
# them against the CWD, so anchor every spawned process there.
Set-Location $RootDir

$Nurlc   = Join-Path $RootDir 'build\nurlc.exe'
$Runtime = Join-Path $RootDir 'stdlib\runtime.o'
$OutDir  = Join-Path $ScriptDir 'outputs-windows'
$WorkDir = Join-Path (Join-Path $RootDir 'build\tests') ('run.' + [guid]::NewGuid().ToString('N'))

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
$CompileTimeout = if ($env:NURL_COMPILE_TIMEOUT) { [double]$env:NURL_COMPILE_TIMEOUT } else { 60 }
if ($CompileTimeout -le 0) { throw 'NURL_COMPILE_TIMEOUT must be positive' }
$Jobs        = if ($env:NURL_TEST_JOBS){ [int]$env:NURL_TEST_JOBS} else { [Environment]::ProcessorCount }
$EnableLive     = if ($env:NURL_LIVE_TESTS) { $env:NURL_LIVE_TESTS } else { '1' }
$EnableFibers   = if ($env:NURL_FIBER_TESTS) { $env:NURL_FIBER_TESTS } else { '1' }
$EnableInternet = if (($env:NURL_HTTP_TESTS -eq '1') -or ($env:NURL_NET_TESTS -eq '1')) { '1' } else { '0' }

New-Item -ItemType Directory -Force -Path $OutDir, $WorkDir | Out-Null
Write-Host "Artifacts: $WorkDir"

# ── CPU tiers: ask the runtime ──────────────────────────────────
# `cpu-vaes` / `cpu-vaes512` / `cpu-ifma` mean "the program's tier gate
# lets the tier run", and the gate is nurl_cpu_x86_* in runtime.o — so
# that is what answers, through a probe linked against the same object
# the tests link, in this process's environment (NURL_CPU_VAES=0 & co
# turn a tier off for it exactly as for the tests). runtime.o and clang
# were found above, so a probe that will not build or answer is a broken
# setup, reported as one — not read as "no tiers", which would turn the
# breakage into silent skips.
$CpuTiers = @{ 'cpu-vaes' = $false; 'cpu-vaes512' = $false; 'cpu-ifma' = $false }
if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') {
    $probeC   = Join-Path $WorkDir 'cpu_probe.c'
    $probeExe = Join-Path $WorkDir 'cpu_probe.exe'
    [System.IO.File]::WriteAllText($probeC, @'
#include <stdio.h>
int nurl_cpu_x86_vaes(void);
int nurl_cpu_x86_vaes512(void);
int nurl_cpu_x86_ifma(void);
int main(void) {
    printf("%d %d %d\n", nurl_cpu_x86_vaes(), nurl_cpu_x86_vaes512(), nurl_cpu_x86_ifma());
    return 0;
}
'@)
    $probeLog = & $Clang $probeC $Runtime '-lwinhttp' @WinLibs '-o' $probeExe 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $probeExe)) {
        Write-Error "CPU-tier probe failed to link against runtime.o:`n$probeLog"; exit 2
    }
    $bits = @(((& $probeExe) | Out-String).Trim() -split '\s+')
    if ($LASTEXITCODE -ne 0 -or $bits.Count -ne 3) {
        Write-Error "CPU-tier probe gave no answer: '$($bits -join ' ')'"; exit 2
    }
    $CpuTiers['cpu-vaes']    = $bits[0] -eq '1'
    $CpuTiers['cpu-vaes512'] = $bits[1] -eq '1'
    $CpuTiers['cpu-ifma']    = $bits[2] -eq '1'
}

# ── collect the test set (ordinal sort, LC_ALL=C equivalent) ─────
$names = @(Get-ChildItem -Path $ScriptDir -Filter '*.nu' -File | ForEach-Object { $_.BaseName })
if ($names.Count -eq 0) { Write-Error "no .nu files in $ScriptDir"; exit 2 }
[Array]::Sort($names, [System.StringComparer]::Ordinal)
if ($Only) {
    foreach ($name in $Only) {
        if ($name -cnotin $names) { throw "Unknown fixture: $name" }
    }
    $names = $Only
}
if (@($names | Select-Object -Unique).Count -ne $names.Count) { throw 'Duplicate selected tests' }

$updateFlag = [bool]$Update

# ── one pipe for a test's stdout AND stderr (agora #256) ────────
# run_tests.sh runs a test as `./name > out 2>&1`: both streams are one
# pipe, so the record holds the lines in the order the program wrote
# them. .NET's Process can only give a child two pipes, and joining them
# afterwards put every stderr line after all of stdout — eight Windows
# goldens recorded that reordering instead of the program's output
# (stdout_flush_order, the check of the runtime's flush order, among
# them). So a test starts the way cmd's `2>&1` starts it: CreateProcess
# with ONE pipe as both hStdOutput and hStdError, stdin NUL. Loaded once
# here; the parallel workers share the process, and so the type.
if (-not ('NurlMergedRun' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public static class NurlMergedRun {
    [StructLayout(LayoutKind.Sequential)]
    struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; public int bInheritHandle; }
    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFO {
        public int cb; public IntPtr lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CreatePipe(out IntPtr r, out IntPtr w, ref SECURITY_ATTRIBUTES sa, int size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, ref SECURITY_ATTRIBUTES sa,
                                     uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attr, IntPtr value,
                                                 IntPtr size, IntPtr prev, IntPtr retSize);
    [DllImport("kernel32.dll")]
    static extern void DeleteProcThreadAttributeList(IntPtr list);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
                                      uint flags, IntPtr env, string cwd, ref STARTUPINFOEX si,
                                      out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetExitCodeProcess(IntPtr h, out uint code);

    const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000, CREATE_UNICODE_ENVIRONMENT = 0x00000400,
               CREATE_NO_WINDOW = 0x08000000, STARTF_USESTDHANDLES = 0x00000100,
               WAIT_TIMEOUT = 0x102, HANDLE_FLAG_INHERIT = 1;
    static readonly IntPtr PROC_THREAD_ATTRIBUTE_HANDLE_LIST = (IntPtr)0x00020002;

    // The child's environment block: the runner's own plus `extra`, sorted
    // the way Windows wants it (case-insensitive by name).
    static IntPtr EnvBlock(IDictionary extra) {
        var env = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (DictionaryEntry e in Environment.GetEnvironmentVariables()) env[(string)e.Key] = (string)e.Value;
        if (extra != null) foreach (DictionaryEntry e in extra) env[(string)e.Key] = (string)e.Value;
        var sb = new StringBuilder();
        foreach (var kv in env) sb.Append(kv.Key).Append('=').Append(kv.Value).Append('\0');
        sb.Append('\0');
        return Marshal.StringToHGlobalUni(sb.ToString());
    }

    // Run `exe` in `cwd` with its stdout and stderr on ONE pipe. Returns
    // { exit code, or 124 when it ran past `timeoutMs` and was killed with
    // its whole tree; everything it wrote, decoded as UTF-8 }.
    public static object[] Run(string exe, string cwd, int timeoutMs, IDictionary extraEnv) {
        var sa = new SECURITY_ATTRIBUTES {
            nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)), bInheritHandle = 1 };
        IntPtr rd, wr;
        if (!CreatePipe(out rd, out wr, ref sa, 0)) throw new Win32Exception();
        // The read end is ours alone.
        SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);
        IntPtr nul = CreateFileW("NUL", 0x80000000 /* GENERIC_READ */, 3 /* share r|w */, ref sa,
                                 3 /* OPEN_EXISTING */, 0, IntPtr.Zero);
        if (nul == (IntPtr)(-1)) { CloseHandle(rd); CloseHandle(wr); throw new Win32Exception(); }
        var reader = new FileStream(new SafeFileHandle(rd, true), FileAccess.Read, 65536);
        Task<byte[]> drain = Task.Run(() => {
            var ms = new MemoryStream();
            reader.CopyTo(ms);
            return ms.ToArray();
        });

        IntPtr size = IntPtr.Zero;
        InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
        IntPtr attrs = Marshal.AllocHGlobal(size);
        IntPtr handles = Marshal.AllocHGlobal(2 * IntPtr.Size);
        IntPtr envBlock = EnvBlock(extraEnv);
        bool listMade = false;
        PROCESS_INFORMATION pi;
        try {
            if (!InitializeProcThreadAttributeList(attrs, 1, 0, ref size)) throw new Win32Exception();
            listMade = true;
            // The only handles the child inherits: sixteen workers create
            // inheritable pipes at once, and a sibling's write end leaked
            // into this child would hold that sibling's read open until
            // this child exits.
            Marshal.WriteIntPtr(handles, 0, wr);
            Marshal.WriteIntPtr(handles, IntPtr.Size, nul);
            if (!UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, handles,
                                           (IntPtr)(2 * IntPtr.Size), IntPtr.Zero, IntPtr.Zero))
                throw new Win32Exception();
            var si = new STARTUPINFOEX();
            si.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
            si.StartupInfo.dwFlags = (int)STARTF_USESTDHANDLES;
            si.StartupInfo.hStdInput = nul;
            si.StartupInfo.hStdOutput = wr;
            si.StartupInfo.hStdError = wr;
            si.lpAttributeList = attrs;
            // argv[0] is the full path, as Process.Start gave it.
            var cmd = new StringBuilder("\"" + exe + "\"");
            if (!CreateProcessW(exe, cmd, IntPtr.Zero, IntPtr.Zero, true,
                                EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                                envBlock, cwd, ref si, out pi)) {
                string why = new Win32Exception(Marshal.GetLastWin32Error()).Message;
                CloseHandle(wr);
                CloseHandle(nul);
                drain.Wait();
                reader.Dispose();
                return new object[] { -1, "run failed: " + why + "\n" };
            }
        } finally {
            if (listMade) DeleteProcThreadAttributeList(attrs);
            Marshal.FreeHGlobal(attrs);
            Marshal.FreeHGlobal(handles);
            Marshal.FreeHGlobal(envBlock);
        }
        // Only the child (and whatever it hands the pipe on to) holds the
        // write end now: the read ends when the last of them exits.
        CloseHandle(wr);
        CloseHandle(nul);
        CloseHandle(pi.hThread);
        int code;
        if (WaitForSingleObject(pi.hProcess, (uint)timeoutMs) == WAIT_TIMEOUT) {
            try { Process.GetProcessById(pi.dwProcessId).Kill(true); } catch (Exception) { }
            WaitForSingleObject(pi.hProcess, 0xFFFFFFFF);
            code = 124;
        } else {
            uint c;
            GetExitCodeProcess(pi.hProcess, out c);
            code = unchecked((int)c);
        }
        CloseHandle(pi.hProcess);
        byte[] bytes = drain.Result;
        reader.Dispose();
        return new object[] { code, new UTF8Encoding(false).GetString(bytes) };
    }
}
'@
}

# ── run in parallel ─────────────────────────────────────────────
# Each worker is self-contained: it compiles, links, runs, then
# compares/updates its own golden and returns a verdict object.
# Writing distinct golden files from parallel threads is race-free.
$results = $names | ForEach-Object -ThrottleLimit $Jobs -Parallel {
    $ErrorActionPreference = 'Stop'
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
    $CompileTimeout = $using:CompileTimeout
    $Update      = $using:updateFlag
    $EnableLive     = $using:EnableLive
    $EnableFibers   = $using:EnableFibers
    $EnableInternet = $using:EnableInternet
    $CpuTiers       = $using:CpuTiers

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
        # nurlc emits UTF-8; decode it as UTF-8 rather than as whatever the
        # console's OEM code page happens to be. Load-bearing twice over —
        # the compiler's stdout IS the .ll we hand to clang below, so an
        # OEM-decoded round trip corrupts every non-ASCII string literal in
        # the program, not just the diagnostics.
        $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $psi.StandardErrorEncoding  = [System.Text.UTF8Encoding]::new($false)
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $o = $proc.StandardOutput.ReadToEndAsync()
        $e = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit([int]($CompileTimeout * 1000))) {
            $proc.Kill($true)
            $proc.WaitForExit()
            throw "Tool timed out after ${CompileTimeout}s: $exe"
        }
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
        # Same rule for this invocation's own artifact directory. The
        # runner names it build\tests\run.<guid> so concurrent runs cannot
        # overwrite each other, and argv_test prints argv[0] — so without
        # this the record carries a name that is new on every run and the
        # golden can never match again. Collapse it to the stable form.
        $leaf = Split-Path -Leaf $WorkDir
        $s = $s -replace [regex]::Escape('build\tests\' + $leaf + '\'), 'build\tests\'
        $s = $s -replace [regex]::Escape('build/tests/' + $leaf + '/'), 'build/tests/'
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
    # Run a native exe to completion, with timeout: its stdout and stderr
    # through ONE pipe, in the order it wrote them (`2>&1` in
    # run_tests.sh; NurlMergedRun above), decoded as UTF-8 as the NURL
    # runtime writes it, and the exit code (124 on timeout, matching
    # `timeout`). Full-path launch + working directory: argv[0] is the
    # absolute path, which Strip-Root rewrites to a repo-relative form.
    function Invoke-WithTimeout([string]$exe, [string]$cwd, [int]$secs) {
        # Windows auto-flags exes whose name contains "install"/"setup"/etc.
        # as requiring UAC elevation (installer-detection heuristic), which
        # makes the launch fail for e.g. pkg_install_e2e.exe. RunAsInvoker
        # suppresses that so the test runs unprivileged like on Linux.
        $r = [NurlMergedRun]::Run($exe, $cwd, $secs * 1000, @{ '__COMPAT_LAYER' = 'RunAsInvoker' })
        return @{ Code = [int]$r[0]; Out = [string]$r[1] }
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

    # Explicit helper intent; entry points and filename suffixes do not
    # distinguish parser rejection fixtures from imported modules.
    $mode = $null
    foreach ($line in [System.IO.File]::ReadLines((Join-Path $ScriptDir "$name.nu"))) {
        if ($line -match '^\s*$') { continue }
        if ($line -notmatch '^\s*//') { break }
        if ($line -match '^\s*//\s*fixture:\s*([^;\s]+)') { $mode = $Matches[1]; break }
    }
    $expectedGold = $gold
    if (-not (Test-Path -LiteralPath $expectedGold)) {
        $expectedGold = Join-Path (Join-Path $ScriptDir 'outputs') "$name.txt"
    }
    if (-not $mode) {
        if ($name -match '^(diag_|borrow_|should_fail_|arity_strict_)' -or
            (Read-TextOrEmpty $expectedGold) -match '^COMPILE FAIL\r?\n') { $mode = 'reject' }
        elseif ($name -like 'lint_*') { $mode = 'compile' }
        else { $mode = 'run' }
    }
    if ($mode -notin @('module', 'reject', 'compile', 'run')) { throw "Invalid test mode: $mode" }
    if ($mode -eq 'module' -and (Test-Path -LiteralPath $expectedGold)) { throw "Module has a test golden: $name" }

    # ── is_skipped ──────────────────────────────────────────────
    $skip = $false
    if ($mode -eq 'module') { $skip = $true }
    # POSIX-only surfaces with no Windows equivalent: termios raw mode and
    # AF_UNIX socketpair. Their link errors are environment text (lld/MSVC
    # version-dependent), so golden-ing the failure is brittle — skip.
    elseif (@('term_basic','unixsock') -contains $name) { $skip = $true }
    # std/fswatch.nu is Linux-only (inotify is a Linux kernel API) — the
    # posix runner skips it everywhere but Linux, and so do we. Its old
    # Windows golden RECORDED the link failure, which is a blessed
    # breakage, not coverage.
    elseif ($name -like 'fswatch_*') { $skip = $true }
    elseif ($name -like 'fdlimit_*') { $skip = $true }
    # Linux-only in test_skips.sh too: its black hole is Linux dropping
    # SYNs to a full accept queue, and its "refused at once" is Linux
    # answering a SYN to a closed port with RST — Windows retries the SYN
    # for about two seconds first.
    elseif ($name -eq 'net_connect_fiber_timeout') { $skip = $true }
    # fs_glob_symlink builds a symlinked directory under /tmp and globs
    # through it. Windows has neither an unprivileged symlink() nor /tmp.
    # It first declared `requires: ln` as a capability probe, on the
    # reasoning that a host without `ln` is a host without symlinks —
    # which is false HERE specifically: this runner has Git for Windows
    # on PATH, so `ln.exe` resolves, the gate passed, and the test ran
    # and failed. A POSIX-only test belongs in this list, next to the
    # termios and AF_UNIX ones, not behind a command-presence guess.
    elseif ($name -eq 'fs_glob_symlink') { $skip = $true }
    # http_static_symlink plants symlinks inside a served directory —
    # the same unprivileged symlink() Windows lacks.
    elseif ($name -eq 'http_static_symlink') { $skip = $true }
    else {
        foreach ($tok in (Get-Requires (Join-Path $ScriptDir "$name.nu"))) {
            switch ($tok) {
                'live'     { if ($EnableLive     -ne '1') { $skip = $true } }
                'fibers'   { if ($EnableFibers   -ne '1') { $skip = $true } }
                # The hardware crypto tier (AES-NI + PCLMULQDQ): every
                # x64 Windows host this runs on has it; NURL_CPU_AES=0
                # turns it off here as it does in the runtime. (Windows on
                # ARM builds no AArch64 crypto tier: skipped there.)
                'cpu-aes'  { if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -or $env:NURL_CPU_AES -eq '0') { $skip = $true } }
                # Answered by the runtime's own gates (the probe above).
                'cpu-vaes'    { if (-not $CpuTiers['cpu-vaes'])    { $skip = $true } }
                'cpu-vaes512' { if (-not $CpuTiers['cpu-vaes512']) { $skip = $true } }
                'cpu-ifma'    { if (-not $CpuTiers['cpu-ifma'])    { $skip = $true } }
                'ktls'     { $skip = $true }
                'internet' { if ($EnableInternet -ne '1') { $skip = $true } }
                # Anything else names an external command the test shells
                # out to. Absent tool → skip, so a stripped host degrades
                # to running less rather than failing on someone else's
                # missing package.
                #
                # -CommandType Application is load-bearing, and it is the
                # Windows half of `command -v`: a bare Get-Command also
                # resolves PowerShell's own aliases, and `cat` is one of
                # them (→ Get-Content). A test that spawns cat(1) would
                # then pass the gate on a host that has no cat.exe at all
                # and fail with ProcessNotFound. Only a real executable
                # on PATH counts.
                default    { if (-not (Get-Command $tok -CommandType Application -ErrorAction SilentlyContinue)) { $skip = $true } }
            }
            if ($skip) { break }
        }
    }
    if ($skip) { return [pscustomobject]@{ Name = $name; Verdict = 'SKIP'; Diff = '' } }

    # ── build the actual record ─────────────────────────────────
    $act = $null

    $enc0 = New-Object System.Text.UTF8Encoding $false

    $nargs = @()
    if ($name -like 'borrow_strict_*') { $nargs += '--strict-borrowck' }
    elseif ($name -like 'nobck_*') { $nargs += '--no-borrowck' }
    elseif ($name -like 'lint_*') { $nargs += '--lint' }
    elseif ($name -like 'arity_strict_*') { $nargs += '--strict-arity' }
    $r = Run-Proc $Nurlc ($nargs + @($src)) $RootDir
    $cc = $r.Code
    $cerr = Normalize $r.Err
    if ($cc -notin @(0, 1)) { throw "Compiler failed with exit ${cc}: $cerr" }
    if (($mode -eq 'reject' -and $cc -ne 1) -or ($mode -ne 'reject' -and $cc -ne 0)) {
        # Optional native library availability is not a compiler defect.
        if ($mode -eq 'run' -and $cerr -match 'no build-time sentinel') {
            return [pscustomobject]@{ Name = $name; Verdict = 'SKIP'; Diff = '' }
        }
        return [pscustomobject]@{ Name = $name; Verdict = 'FAIL'; Diff = "Unexpected compiler exit $cc for $mode fixture: $cerr" }
    }
    if ($mode -eq 'reject') {
        $act = "COMPILE FAIL`n"
        if ($name -notlike 'should_fail_*' -and $cerr.Length -gt 0) {
            $act += "ERRORS`n" + (Cap-Lines (Strip-Root $cerr))
        }
    }
    elseif ($mode -eq 'compile') {
        $act = "COMPILE OK`n"
        if ($cerr.Length -gt 0) { $act += "WARNINGS`n" + (Cap-Lines (Strip-Root $cerr)) }
    }
    else {
        $isWarn = $name -like 'should_warn_*'
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

            if ($r.Code -eq 124) { throw "Runtime timed out: $name" }
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
        $temporary = $gold + '.tmp.' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllText($temporary, $act, $enc)
            [System.IO.File]::Move($temporary, $gold, $true)
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
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

# Every selected test must yield exactly one recognized record. A worker
# exception or unexpected pipeline output cannot silently shrink coverage.
$seen = @{}
foreach ($r in $results) {
    if ($null -eq $r -or $r.Name -cnotin $names -or
        $r.Verdict -cnotin @('PASS', 'FAIL', 'MISSING', 'UPDATED', 'SKIP')) {
        throw "Invalid test verdict: $r"
    }
    if ($seen.ContainsKey($r.Name)) { throw "Duplicate test verdict: $($r.Name)" }
    $seen[$r.Name] = $true
}
foreach ($name in $names) {
    if (-not $seen.ContainsKey($name)) { throw "Missing test verdict: $name" }
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
    Write-Host "Updated $updated golden(s); skipped $skip; failed $fail."
    foreach ($f in $failed) { Write-Host "$($f.Name): $($f.Diff)" }
    if ($orphans.Count -gt 0) {
        Write-Host "NOTE: $($orphans.Count) orphan golden(s) remain (no .nu): $($orphans -join ' ')"
    }
    if ($fail -gt 0 -or $missing -gt 0 -or $orphans.Count -gt 0) { exit 1 }
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
