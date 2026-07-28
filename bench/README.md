# NURL benchmarks

Fifteen benchmarks. Five languages each — **NURL**, **C**, **Rust**,
**Node** and **Python** — one algorithm per benchmark, one runner, one
report. A row is timed only when all five implementations print the same
line, so no cell can be fast by computing something else.

Two runners read the same roster: `bench.sh` compares languages on the
native target, and [`wasmbench.sh`](#the-wasm-suite--wasmbenchsh) compares
native against `wasm32-wasi` on two runtimes.

```sh
./build.sh                 # build/nurlc + stdlib/runtime.o must exist first
./bench/bench.sh           # the whole suite (~10 min; Python is the long pole)
./bench/bench.sh --quick   # one run per cell, for a smoke test
./bench/bench.sh --bench lcg --bench sieve
./bench/bench.sh --stdout  # print the report, write nothing
```

It writes two files:

| File | For | Contents |
|---|---|---|
| [`results/latest.json`](results/latest.json) | machines | Run times, compile times, checksums, host and toolchain versions. The landing page's benchmark table is generated from this file at publish time by `tools/gen-bench-table.mjs`. |
| [`RESULTS.md`](RESULTS.md) | humans | The same run rendered: run times, compile times, the correctness gate, and the process-start-up floor. |

Both are refreshed by [`.github/workflows/bench.yml`](../.github/workflows/bench.yml)
on a fixed `ubuntu-latest` runner — weekly, and on demand from the Actions
tab. Those runs commit the refreshed files, which is how nurl-lang.org's
numbers stay honest without anyone typing a figure into HTML.

## On Windows — `bench.ps1`

[`bench.ps1`](bench.ps1) is the same suite, same manifest, same protocol,
for a Windows box. It needs `build.bat` to have run, plus clang, rustc,
node and a Python the `py` launcher can find.

```powershell
build.bat --no-tests               # build\nurlc.exe + stdlib\runtime.o
pwsh bench\bench.ps1               # the whole suite
pwsh bench\bench.ps1 -Quick        # one run per cell, for a smoke test
pwsh bench\bench.ps1 -Bench lcg,sieve
pwsh bench\bench.ps1 -Stdout       # print the report, write nothing
```

It writes [`results/latest-windows.json`](results/latest-windows.json) and
`RESULTS-WINDOWS.md`, deliberately **not** the two files above: those are
the Linux CI numbers the landing page publishes, and a local Windows run
must not be able to end up in that table by accident.

## The contract

Every implementation of a benchmark:

1. takes no arguments and reads no input except `data.json` where the
   benchmark says so;
2. computes a checksum and **prints exactly one line** — that value in
   decimal, masked to 63 bits so the languages without an unsigned
   64-bit type can print it too;
3. prints nothing else.

`bench.sh` runs all five, compares the five lines, and only then times
them. A mismatch fails the run rather than producing a table with a
plausible-looking wrong cell in it.

The `// benchmark-contract:` line at the top of each source file is the
algorithm's parameters in one line — seed, iteration count, constants —
so the five files can be checked against each other by reading, not just
by running.

## The roster

Defined in [`manifest.tsv`](manifest.tsv), which is what both `bench.sh`
and `perfstat.sh` read.

| Benchmark | Shape |
|---|---|
| `lcg` | Loop-carried mul/add/shift/xor dependency the unroller cannot compose |
| `packet_classifier` | A data-dependent 50/50 branch the predictor cannot learn |
| `ring_write` | Dependent store per iteration plus address computation |
| `histogram_bins` | Read-modify-write at a data-dependent index |
| `prefix_scan` | Store-bound fill, then a serial load/add dependency chain |
| `binary_search` | Pointer-chasing: each load address depends on the last compare |
| `sort_window` | Branchless compare/exchange mill over a 64-byte window |
| `bloom_filter` | Four unpredictable loads per query over a 2 KB working set |
| `hash_join` | Cheap Bloom early-out plus a rare, branchy join path |
| `sieve` | Irregular-stride byte writes, then one linear scan |
| `fib` | The call/return path: ~15M calls after LLVM turns one recursion into a loop |
| `collatz` | Control-flow-heavy inner loop with no array at all |
| `matmul` | Triple-nested loop, flat indexing, column-strided reads |
| `json_parse` | Allocator pressure, string handling, recursive descent |
| `nbody` | IEEE-754 doubles: sqrt and divide throughput, the FPU rather than the ALU |

No two rows measure the same shape. That is a deliberate property, and
the reason the previous `stream_lcg` kernel is gone: it was `lcg` with
32-bit constants, so it made the table longer without making it say more.

`nbody` is the one row not defined over integers, and it is here for two
reasons. It is the only one whose critical path runs through the FPU's
long-latency, non-pipelined sqrt and divide units rather than the integer
ALU — nothing else in the roster exercises that hardware, or NURL's `f`
codegen, at all. And it is the only row where JavaScript competes on even
terms: see below.

### How the languages are held to the same algorithm

Nine of the fifteen are defined over 64-bit unsigned integers, which two
of the five languages do not have:

* **Python** has arbitrary-precision integers, so every step masks
  explicitly. Always exact, and slow — that is the measurement.
* **JavaScript** has no 64-bit integer at all. Where the algorithm
  genuinely needs 64 bits (`lcg`, `bloom_filter`, `hash_join`) the port
  uses `BigInt`; where 32 bits suffice it uses
  Numbers with `Math.imul`, which is exactly defined as the wrapping
  32-bit multiply. Each file states which and why in its header.

The rule is *each language at its fastest exact representation*, and the
checksum gate is what keeps "fastest" from drifting into "different".

`nbody` is the counterweight to those two bullets. It is defined over
IEEE-754 doubles, which is precisely the type JavaScript *does* have —
its single numeric type is the double, and `Math.sqrt` is the same
correctly-rounded hardware instruction the compiled backends emit. So
Node runs the identical arithmetic there with no representation tax, and
lands around 2× C rather than the 30–50× the BigInt rows cost it. That
matters for reading the whole table: a suite in which one language loses
every row by two orders of magnitude invites the suspicion that the
corpus was chosen to make it lose, and the cheapest way to answer that is
to include the row where it doesn't.

Bit-exactness across five languages is not free, and `nbody` holds three
lines to get it:

* **No `-ffast-math`, and no multiply-add contraction.** Fusing
  `dx*dx + dy*dy` into an fma is *more* accurate than the unfused form,
  which is exactly the problem: JS and Python cannot fuse and would
  disagree in the last bits. This is moot as the suite is built today —
  the baseline `x86-64` target has no FMA instruction and `bench.sh`
  sets no `-march` — so if a `-march=` flag is ever added, that row needs
  an explicit `-ffp-contract=off`. Its header says so.
* **The same operation order in all five files.** IEEE addition is not
  associative, so a reordered sum is a different number.
* **The same data layout in all five files** — struct-of-arrays. An
  array-of-structs C port is ~6% faster (274.0M retired instructions
  against SoA's 290.1M), but mixing the two layouts would have had the
  row reporting a 6% spread that has nothing to do with floating point.
  Pinned to one layout, the three compiled backends land within 3.5% of
  each other on instruction count. SoA is the layout that is natural in
  all five at once: an AoS Python port would be a list of objects and
  would measure the interpreter's object model instead of its float path.

What is left is IEEE-754 exact by specification — `+`, `-`, `*`, `/` and
`sqrt` are all correctly rounded — so five conforming implementations
evaluating the same expressions in the same order must agree to the bit.
The row prints the bit pattern of the final energy, so the gate asserts
exactly that.

## What is **not** in the timing suite

* `brackets`, `csv_sum`, `histogram`, `quicksort`, `rot13` and `words`
  are the held-out corpus for the generation-accuracy study in
  [`genacc/`](genacc/) and the token study in
  [`TOKEN_EFFICIENCY.md`](TOKEN_EFFICIENCY.md). Their workloads are a
  single short string: they measure process start-up, not a language.
  [`verify.sh`](verify.sh) is their cross-language correctness gate.

  `genacc/` is self-contained: each task's prompt *and* its expected
  output are pinned in [`genacc/tasks.json`](genacc/tasks.json), and the
  scorer never reads the files here. So a benchmark that appears in both
  places can hold a different workload in each — `matmul` is 256×256 in
  the timing suite (128×128 was too small to measure) and stays 128×128
  in the frozen genacc task, whose recorded model scores would otherwise
  stop describing the task they were measured against.
* `http_server.{nu,js}` + `rust_http_server/` are the HTTP-server peer
  benchmark, driven by [`run_http.sh`](run_http.sh) with `oha` as the
  load generator; results in [`HTTP_RESULTS.md`](HTTP_RESULTS.md). It
  measures requests per second, not wall clock, so it has its own runner.
* `stdlib_hotpath.nu` is a NURL-only profiling probe with no peers.

## The wasm suite — `wasmbench.sh`

[`wasmbench.sh`](wasmbench.sh) is the same corpus with one axis rotated.
`bench.sh` asks how fast NURL is against four other languages;
`wasmbench.sh` asks what **targeting wasm** costs, and what running that
wasm on **NURL's own runtime** costs:

```sh
./bench/wasmbench.sh                 # the whole suite (~15 min)
./bench/wasmbench.sh --wt-all-langs  # + C/Rust on the interpreter (~45 min)
./bench/wasmbench.sh --quick --bench lcg
```

Everything but the interpreter column costs about what `bench.sh` does;
the interpreter is ~500× native, so it is the whole budget. Running the C
and Rust modules on it too — the cross-frontend control — triples that, so
it is opt-in.

Each benchmark's NURL, C and Rust sources are compiled **twice** — native
and `wasm32-wasi` — and each module is run on **two** runtimes: the
reference `wasmtime` (Cranelift JIT) and
[`packages/wasmtime`](../packages/wasmtime), a WebAssembly interpreter
written in pure NURL. Ten timed cells per row, all gated on printing the
same line as the native NURL binary — the interpreter is *inside* the
gate, because a runtime that gets the wrong answer quickly is not a fast
runtime. Results: [`WASMRESULTS.md`](WASMRESULTS.md) and
[`results/wasm-latest.json`](results/wasm-latest.json).

The tenth cell is the NURL module relinked with `--no-gc-sections` —
`wasmbuilder`'s pre-0.1.4 default, kept measured so the price of its
escape hatch stays a number (section 5 of the report). See
[`packages/wasmbuilder`](../packages/wasmbuilder/README.md#--gc-sections-is-the-default-and---no-gc-sections-the-escape-hatch)
for why the default flipped and what would justify flipping it back.

C and Rust are there as the control. Without them a wasm-vs-native ratio
cannot distinguish "wasm is slower here" from "NURL's wasm pipeline is
slower here", and modules from two other LLVM frontends are the only
honest test of a runtime written against NURL's own output.

The pieces are all built from this repo rather than from an installed
toolchain — `nurlc`, `stdlib/runtime.o`,
[`packages/wasmbuilder`](../packages/wasmbuilder) (NURL → wasm) and
`packages/wasmtime` (the runtime) — so the numbers describe this working
tree. What it additionally needs on the host is `zig` (wasi-libc +
`wasm-ld`, and the NURL toolchain bundles one), `rustup target add
wasm32-wasip1`, and a reference `wasmtime`, which is deliberately *not*
vendored here: its whole job is to be the outside opinion.

## Beyond wall clock

[`perfstat.sh`](perfstat.sh) builds the NURL binaries and reports
**retired instructions and core cycles** from the CPU's own counters:

```sh
./bench/perfstat.sh --save ref.tsv     # record a baseline
./bench/perfstat.sh --against ref.tsv  # compare after a compiler change
```

Wall clock has several per cent of run-to-run drift, so anything under
~10 % there is noise. Instructions are essentially deterministic for
these single-threaded kernels and cycles do not move with the frequency
governor, which makes a 1 % regression visible. Use `bench.sh` to compare
languages, `perfstat.sh` to compare two versions of NURL.

## Physical floors — `chaincheck.sh`

A serial-chain row must not run faster than its dependency chain's
hardware minimum: `lcg`'s step is `imul(3)+add(1)+shr(1)+xor(1)` = 6
cycles, so 20M iterations cannot legitimately finish under 120M cycles.
`./bench/chaincheck.sh` builds the NURL, C and Rust binaries the way
`bench.sh` does and verifies every chain row against its documented
floor — with exact PMU cycle counts where `perf` works (a healthy row
sits within ~10 % of its floor; the current table measures 6.02–6.03
cyc/iter on `lcg` for all three languages), and as a wall-clock lower
bound at 6 GHz on PMU-less CI runners. The bench workflow runs it after
every suite run: a table with an impossible number in it fails the run
instead of getting published.

This gate exists because the pre-xorshift `lcg` was exactly such a
number — LLVM composed k affine steps into one (`x·aᵏ + cₖ`), the NURL
binary ran 100M "iterations" in 3.7 ms (a 162 GHz clock, had the chain
been real), and the row was silently measuring the compiler's
composition factor. The xorshift mix in `lcg`, `ring_write` and
`histogram_bins` breaks the affinity that transform needs;
`chaincheck.sh` keeps it broken.

## Reading the numbers

* Compare a cell against the **floor row** in `RESULTS.md` (an empty
  program in the same language). A cell near the floor is process
  start-up, not the benchmark.
* All three compiled back ends are LLVM-based and all three are allowed
  to be clever — LLVM will fold an affine recurrence or pick a different
  unroll factor per language. A cell measures optimised throughput of the
  same algorithm, not the source-level iteration count.
* Absolute numbers are machine-specific. Compare deltas between runs on
  the same machine or the same CI runner spec; the committed results
  file always records which host produced it.
