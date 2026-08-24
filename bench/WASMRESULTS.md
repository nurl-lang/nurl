# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T07:31:05Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-latest.json`](results/wasm-latest.json).

This is the sibling of [`RESULTS.md`](RESULTS.md): same corpus, same
protocol, one axis rotated. `RESULTS.md` asks how fast NURL is against
four other languages; this file asks what **targeting wasm** costs, and
what running that wasm on **NURL's own runtime** costs. Every benchmark
is compiled to a native binary *and* a `wasm32-wasi` module in three
languages, and each module is run on two runtimes — ten timed cells per
row, all gated on printing the same line (section 7).

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `948fbb197a9f23d814047bc325624e63512e22e9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32701469867 |
| NURL | `v0.50.0-5-g948fbb19` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.0), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.15.0 (pure NURL)) — interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | yes |
| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |
| `wt` build | `NURL_SPLIT=0` — `nurl.sh` otherwise lowers a large program as one module per core, and ThinLTO cannot import every callee back across a part boundary. `wt` is the subject of section 3, and the reference runtime it is measured against is a release build; a split `wt` measured 5.0% slower over this corpus. |

## 1. What wasm costs — native vs the same module on a JIT

Whole-process wall clock in milliseconds, start-up included. The `x`
columns are wasm ÷ native for that language: how much slower the *same
source* got by being compiled to wasm and run under a JIT instead of
straight to the machine. Because all three languages appear, the column
answers a question a NURL-only table could not: whether a gap belongs to
NURL's wasm pipeline or to wasm itself.

| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.452_ | _12.477_ | _8.6_ | _1.566_ | _6.875_ | _4.4_ | _1.630_ | _35.261_ | _21.6_ |
| `lcg` | 39.175 | 67.186 | 1.7 | 39.427 | 66.246 | 1.7 | 39.454 | 74.461 | 1.9 |
| `packet_classifier` | 56.286 | 80.765 | 1.4 | 56.409 | 79.241 | 1.4 | 56.545 | 87.555 | 1.5 |
| `ring_write` | 42.495 | 80.168 | 1.9 | 42.343 | 78.927 | 1.9 | 42.479 | 86.836 | 2.0 |
| `histogram_bins` | 39.623 | 79.315 | 2.0 | 41.438 | 77.043 | 1.9 | 41.402 | 88.108 | 2.1 |
| `prefix_scan` | 21.861 | 40.623 | 1.9 | 21.806 | 38.388 | 1.8 | 21.785 | 48.502 | 2.2 |
| `binary_search` | 39.824 | 90.170 | 2.3 | 38.290 | 92.498 | 2.4 | 38.268 | 98.576 | 2.6 |
| `sort_window` | 27.353 | 80.522 | 2.9 | 27.585 | 58.887 | 2.1 | 27.098 | 69.418 | 2.6 |
| `bloom_filter` | 17.656 | 46.409 | 2.6 | 18.161 | 46.866 | 2.6 | 18.526 | 53.590 | 2.9 |
| `hash_join` | 28.146 | 68.681 | 2.4 | 30.448 | 81.610 | 2.7 | 30.057 | 88.615 | 2.9 |
| `sieve` | 18.790 | 58.143 | 3.1 | 20.272 | 65.106 | 3.2 | 18.284 | 63.286 | 3.5 |
| `fib` | 25.357 | 74.783 | 2.9 | 30.140 | 77.501 | 2.6 | 25.379 | 77.948 | 3.1 |
| `collatz` | 12.301 | 48.547 | 3.9 | 12.346 | 46.007 | 3.7 | 12.525 | 54.593 | 4.4 |
| `matmul` | 33.809 | 56.567 | 1.7 | 34.239 | 51.807 | 1.5 | 33.725 | 62.880 | 1.9 |
| `json_parse` | 9.067 | 51.303 | 5.7 | 8.714 | 42.311 | 4.9 | 11.661 | 60.388 | 5.2 |
| `nbody` | 41.072 | 78.801 | 1.9 | 40.936 | 69.573 | 1.7 | 39.093 | 80.913 | 2.1 |

The floor row matters more here than in `RESULTS.md`. A wasm cell pays
for the runtime compiling the whole module before `_start` runs, and a
NURL module links the entire NURL runtime whatever the program does — so
even the empty program is a ~1 MB module to JIT. Section 2 subtracts that
floor from both ends to show the steady-state ratio.

## 2. The same ratios, with start-up subtracted

Cell minus the floor of its own column, wasm ÷ native. This is the
number to quote for a long-running program, where module compilation is
amortised to nothing; section 1 is the number to quote for a short one,
where it is most of the run.

A `—` means the subtraction has no signal left in it: the floor is more
than half of that cell, so the remainder is a difference of two similar
numbers carrying both their errors. The `no gc` column is the
pre-0.1.4 default relinked with `--no-gc-sections` (section 5); its
floor is big enough that most of its rows land there, which is one of
the reasons it is no longer the default.

| Benchmark | NURL x | NURL no-gc x | C x | Rust x |
|---|---:|---:|---:|---:|
| `lcg` | 1.5 | — | 1.6 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.6 | — | 1.8 | 1.3 |
| `histogram_bins` | 1.8 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.4 | — | 1.6 | — |
| `binary_search` | 2.0 | — | 2.3 | 1.7 |
| `sort_window` | 2.6 | — | 2.0 | — |
| `bloom_filter` | 2.1 | — | 2.4 | — |
| `hash_join` | 2.1 | — | 2.6 | 1.9 |
| `sieve` | 2.6 | — | 3.1 | — |
| `fib` | 2.6 | — | 2.5 | 1.8 |
| `collatz` | 3.3 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.1 | — | 5.0 | — |
| `nbody` | 1.7 | — | 1.6 | 1.2 |

## 3. The pure-NURL runtime (`packages/wasmtime`)

The identical modules from section 1, executed by an interpreter written
in NURL instead of by a JIT written in Rust. `vs JIT` is the cost of the
runtime; `vs native` is the end-to-end cost of choosing this way to ship.
Losing orders of magnitude to a JIT is the shape an interpreter has; the
point of the column is that the size of the gap is measured rather than
assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing the interpreter *beats* the JIT. Nothing surprising is
happening — the JIT compiles the whole module before `_start`, and the
interpreter only decodes it and walks the handful of instructions that
run. That crossover is the honest answer to "which runtime should I
use": it depends entirely on how long the guest runs.

| Benchmark | NURL on `wt` | vs JIT | vs native | C on `wt` | Rust on `wt` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.445_ | _0.2_ | _1.7_ | _2.470_ | _2.806_ |
| `lcg` | 119.272 | 1.8 | 3.0 | 186.538 | 190.013 |
| `packet_classifier` | 326.265 | 4.0 | 5.8 | 311.682 | 362.013 |
| `ring_write` | 442.659 | 5.5 | 10.4 | 443.424 | 452.079 |
| `histogram_bins` | 527.111 | 6.6 | 13.3 | 576.526 | 527.315 |
| `prefix_scan` | 122.051 | 3.0 | 5.6 | 105.957 | 126.125 |
| `binary_search` | 864.635 | 9.6 | 21.7 | 868.852 | 1003.314 |
| `sort_window` | 760.532 | 9.4 | 27.8 | 496.908 | 507.131 |
| `bloom_filter` | 301.027 | 6.5 | 17.0 | 342.239 | 313.333 |
| `hash_join` | 833.200 | 12.1 | 29.6 | 925.491 | 941.632 |
| `sieve` | 500.403 | 8.6 | 26.6 | 484.273 | 435.587 |
| `fib` | 526.132 | 7.0 | 20.7 | 473.602 | 427.279 |
| `collatz` | 191.074 | 3.9 | 15.5 | 180.448 | 193.721 |
| `matmul` | 277.279 | 4.9 | 8.2 | 310.140 | 307.097 |
| `json_parse` | 329.667 | 6.4 | 36.4 | 142.990 | 235.238 |
| `nbody` | 820.310 | 10.4 | 20.0 | 822.232 | 901.137 |

The C and Rust columns are the control. They are modules this runtime
never saw during development, emitted by two other LLVM frontends; that
they run at all is a correctness result, and that they run at a similar
ratio says the interpreter has no NURL-shaped fast path.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 16 | 1092 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 16 | 1092 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1092 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1092 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1092 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1092 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1092 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1092 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1094 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1092 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1092 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1092 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1092 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1118 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1094 | 16 | 919 | 4404 | 2085 |

## 5. Dead code — what `--no-gc-sections` would cost

Every NURL module above was linked with `-Wl,--gc-sections`, the
`wasmbuilder` default since 0.1.4: the unreachable part of the NURL
runtime is dropped instead of shipped and JIT-translated for nothing.
The old default, `--no-gc-sections`, exists as an escape hatch for a
closure/table-renumbering hazard that no longer reproduces — a
`--gc-sections` `nurlc.wasm` self-compiles byte-identically under both
runtimes. These rows are the same benchmarks relinked with the escape
hatch, held to the same output, so its price stays a number: what you
pay in bytes and module-load time if you ever have to reach for it.

| Benchmark | Size | Size no-gc | Δ | JIT | JIT no-gc | Δ |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1072_ | _1393_ | _+30 %_ | _12.477_ | _141.289_ | _+1032 %_ |
| `lcg` | 1092 | 1393 | +28 % | 67.186 | 178.265 | +165 % |
| `packet_classifier` | 1092 | 1393 | +28 % | 80.765 | 190.972 | +136 % |
| `ring_write` | 1092 | 1393 | +28 % | 80.168 | 189.600 | +137 % |
| `histogram_bins` | 1092 | 1393 | +28 % | 79.315 | 188.394 | +138 % |
| `prefix_scan` | 1092 | 1393 | +28 % | 40.623 | 151.237 | +272 % |
| `binary_search` | 1092 | 1393 | +28 % | 90.170 | 199.364 | +121 % |
| `sort_window` | 1092 | 1394 | +28 % | 80.522 | 182.741 | +127 % |
| `bloom_filter` | 1092 | 1393 | +28 % | 46.409 | 160.657 | +246 % |
| `hash_join` | 1094 | 1396 | +28 % | 68.681 | 179.748 | +162 % |
| `sieve` | 1092 | 1393 | +28 % | 58.143 | 180.632 | +211 % |
| `fib` | 1092 | 1393 | +28 % | 74.783 | 192.257 | +157 % |
| `collatz` | 1092 | 1393 | +28 % | 48.547 | 159.117 | +228 % |
| `matmul` | 1092 | 1393 | +28 % | 56.567 | 166.472 | +194 % |
| `json_parse` | 1118 | 1416 | +27 % | 51.303 | 164.773 | +221 % |
| `nbody` | 1094 | 1395 | +27 % | 78.801 | 186.679 | +137 % |

The cost is almost all fixed, so it is largest where the benchmark
itself is smallest — compare each row against the floor. It is reported
on the JIT and not on the interpreter because the interpreter is
execution-bound, not decode-bound: its floor row in section 3 is a few
tens of milliseconds against cells in the tens of *seconds*, so module
size cannot move it either way.

## 6. Compile time (median, ms)

The NURL wasm build is `wasmbuilder`: `nurlc` emits host LLVM IR, the IR
rewriter retargets it for `wasm32-wasi`, and the toolchain-bundled
`zig cc` links it against wasi-libc and a cached `runtime.wasm.o`. The
column is the whole pipeline, comparable to the NURL native total beside
it and to the C and Rust wasm columns.

| Benchmark | NURL `nurlc` | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.666_ | _97.041_ | _59.612_ | _57.849_ | _41.334_ | _55.527_ | _69.083_ |
| `lcg` | 2.807 | 102.139 | 60.230 | 67.766 | 42.744 | 60.557 | 74.909 |
| `packet_classifier` | 2.856 | 104.318 | 59.786 | 68.268 | 41.956 | 60.872 | 74.906 |
| `ring_write` | 3.037 | 107.263 | 59.328 | 69.710 | 41.413 | 62.162 | 76.391 |
| `histogram_bins` | 3.127 | 108.184 | 60.086 | 71.985 | 42.454 | 64.045 | 77.695 |
| `prefix_scan` | 3.109 | 109.357 | 61.753 | 74.634 | 42.335 | 65.914 | 78.970 |
| `binary_search` | 3.232 | 107.701 | 65.887 | 70.751 | 42.281 | 66.828 | 81.040 |
| `sort_window` | 3.281 | 115.757 | 61.536 | 77.503 | 42.751 | 73.365 | 86.058 |
| `bloom_filter` | 3.670 | 116.341 | 64.187 | 80.182 | 43.096 | 69.774 | 83.082 |
| `hash_join` | 6.065 | 233.524 | 72.819 | 122.175 | 43.681 | 105.659 | 120.125 |
| `sieve` | 3.260 | 111.131 | 60.861 | 79.489 | 42.968 | 71.068 | 82.624 |
| `fib` | 2.863 | 102.520 | 61.270 | 67.609 | 41.879 | 59.807 | 73.329 |
| `collatz` | 3.051 | 108.099 | 61.431 | 71.310 | 42.264 | 65.300 | 77.604 |
| `matmul` | 3.419 | 115.201 | 63.477 | 84.122 | 42.271 | 86.704 | 95.816 |
| `json_parse` | 52.450 | 620.599 | 150.074 | 126.635 | 44.129 | 170.297 | 152.147 |
| `nbody` | 4.774 | 126.524 | 70.935 | 97.281 | 42.068 | 87.052 | 99.698 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

## 8. Reading the numbers

* Sections 1 and 3 are whole-process wall clock, so a cell near its
  column's floor is mostly start-up — and on wasm, start-up includes the
  runtime ingesting the module. Section 2 is where the steady-state
  throughput ratio lives.
* Every cell in a row computes the same thing, but not necessarily with
  the same machine code. LLVM optimises for wasm and for x86-64
  differently: wasm has no flags register, no `cmov`, and a JIT compiling
  at load time cannot spend the time an offline `-O2` does. A ratio above
  1 is that difference, not lost work.
* The three languages share a corpus but not a runtime. A NURL module
  carries NURL's allocator and string machinery; a Rust module carries
  Rust's; a C module carries almost nothing. Section 4 is that difference
  in bytes, and part of the floor row is the same difference in time.
* The reference runtime's compiled-module cache is off. Its CLI enables
  that cache by default, which would make a cell mean "Cranelift ran" or
  "Cranelift did not run" depending on what happened to be in
  `~/.cache/wasmtime` — including across the floor row, whose whole job is
  to be subtracted from the others. Off, both runtimes are measured doing
  the same work: read the module, translate it, run it. A deployment that
  keeps the cache (or precompiles with `wasmtime compile`) pays the floor
  once instead of every run — section 2 is the number that survives that.
* `json_parse` reads `bench/data.json`, so every wasm run gets a `--dir .`
  preopen. The other rows pay the same preopen cost and need nothing from
  it, which keeps the column internally comparable.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
