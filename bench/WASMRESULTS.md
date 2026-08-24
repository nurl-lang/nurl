# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T10:39:32Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16373452 KiB |
| Commit | `24ed72a33d35716118872a3f9bf4a881a75329b1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32717573118 |
| NURL | `v0.50.0-9-g24ed72a3` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.0), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.15.0 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.450_ | _11.742_ | _8.1_ | _1.535_ | _7.587_ | _4.9_ | _1.619_ | _38.077_ | _23.5_ |
| `lcg` | 39.230 | 67.007 | 1.7 | 39.327 | 65.838 | 1.7 | 39.389 | 74.048 | 1.9 |
| `packet_classifier` | 56.420 | 81.314 | 1.4 | 56.578 | 78.704 | 1.4 | 56.599 | 87.765 | 1.6 |
| `ring_write` | 42.132 | 78.963 | 1.9 | 42.214 | 78.344 | 1.9 | 42.350 | 86.815 | 2.0 |
| `histogram_bins` | 39.510 | 78.212 | 2.0 | 41.102 | 75.206 | 1.8 | 41.178 | 86.409 | 2.1 |
| `prefix_scan` | 21.630 | 41.024 | 1.9 | 21.741 | 40.084 | 1.8 | 21.876 | 47.269 | 2.2 |
| `binary_search` | 39.576 | 91.600 | 2.3 | 38.311 | 88.978 | 2.3 | 38.103 | 102.692 | 2.7 |
| `sort_window` | 27.412 | 72.918 | 2.7 | 27.423 | 60.448 | 2.2 | 26.899 | 68.884 | 2.6 |
| `bloom_filter` | 17.661 | 48.061 | 2.7 | 18.315 | 45.099 | 2.5 | 18.483 | 51.967 | 2.8 |
| `hash_join` | 27.964 | 67.392 | 2.4 | 30.017 | 80.533 | 2.7 | 29.965 | 89.628 | 3.0 |
| `sieve` | 20.943 | 63.647 | 3.0 | 20.152 | 67.079 | 3.3 | 20.396 | 61.453 | 3.0 |
| `fib` | 25.075 | 74.640 | 3.0 | 30.006 | 70.294 | 2.3 | 25.399 | 78.305 | 3.1 |
| `collatz` | 12.236 | 47.337 | 3.9 | 12.212 | 45.604 | 3.7 | 12.385 | 55.121 | 4.5 |
| `matmul` | 33.649 | 58.422 | 1.7 | 33.629 | 51.212 | 1.5 | 33.867 | 64.703 | 1.9 |
| `json_parse` | 8.919 | 56.089 | 6.3 | 8.647 | 39.071 | 4.5 | 11.716 | 62.519 | 5.3 |
| `nbody` | 40.702 | 88.061 | 2.2 | 40.963 | 67.441 | 1.6 | 39.151 | 75.696 | 1.9 |

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
| `lcg` | 1.5 | — | 1.5 | — |
| `packet_classifier` | 1.3 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.5 | — | 1.6 | — |
| `binary_search` | 2.1 | — | 2.2 | 1.8 |
| `sort_window` | 2.4 | — | 2.0 | — |
| `bloom_filter` | 2.2 | — | 2.2 | — |
| `hash_join` | 2.1 | — | 2.6 | 1.8 |
| `sieve` | 2.7 | — | 3.2 | — |
| `fib` | 2.7 | — | 2.2 | 1.7 |
| `collatz` | 3.3 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.9 | — | 4.4 | — |
| `nbody` | 1.9 | — | 1.5 | — |

## 3. The pure-NURL runtime (`packages/wasmtime`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with a template
JIT on top (on by default; `NURL_WT_JIT=0` keeps the pure interpreter,
and metered or shared-memory runs fall back to it on their own).
`vs JIT` is the cost of the runtime; `vs native` is the end-to-end
cost of choosing this way to ship. The size of the gap is measured
rather than assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing this runtime *beats* the reference. Nothing surprising
is happening — the reference compiles the whole module before `_start`,
and `wt` only decodes it, compiling nothing but what runs. That
crossover is the honest answer to "which runtime should I use": it
depends entirely on how long the guest runs.

| Benchmark | NURL on `wt` | vs JIT | vs native | C on `wt` | Rust on `wt` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.822_ | _0.2_ | _1.9_ | _2.625_ | _3.302_ |
| `lcg` | 41.127 | 0.6 | 1.0 | 41.168 | 41.804 |
| `packet_classifier` | 67.156 | 0.8 | 1.2 | 62.274 | 63.685 |
| `ring_write` | 59.204 | 0.7 | 1.4 | 58.569 | 56.224 |
| `histogram_bins` | 75.315 | 1.0 | 1.9 | 82.060 | 75.652 |
| `prefix_scan` | 31.808 | 0.8 | 1.5 | 30.489 | 32.339 |
| `binary_search` | 217.908 | 2.4 | 5.5 | 206.687 | 248.777 |
| `sort_window` | 275.041 | 3.8 | 10.0 | 232.871 | 233.757 |
| `bloom_filter` | 57.055 | 1.2 | 3.2 | 65.126 | 55.698 |
| `hash_join` | 138.140 | 2.0 | 4.9 | 147.465 | 145.332 |
| `sieve` | 84.599 | 1.3 | 4.0 | 84.516 | 69.374 |
| `fib` | 499.074 | 6.7 | 19.9 | 520.528 | 483.663 |
| `collatz` | 28.018 | 0.6 | 2.3 | 27.770 | 28.669 |
| `matmul` | 50.186 | 0.9 | 1.5 | 50.500 | 49.223 |
| `json_parse` | 126.387 | 2.3 | 14.2 | 53.660 | 157.787 |
| `nbody` | 251.952 | 2.9 | 6.2 | 819.658 | 890.587 |

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
| _(floor: empty program)_ | _1072_ | _1393_ | _+30 %_ | _11.742_ | _146.280_ | _+1146 %_ |
| `lcg` | 1092 | 1393 | +28 % | 67.007 | 176.998 | +164 % |
| `packet_classifier` | 1092 | 1393 | +28 % | 81.314 | 193.020 | +137 % |
| `ring_write` | 1092 | 1393 | +28 % | 78.963 | 189.138 | +140 % |
| `histogram_bins` | 1092 | 1393 | +28 % | 78.212 | 188.354 | +141 % |
| `prefix_scan` | 1092 | 1393 | +28 % | 41.024 | 146.817 | +258 % |
| `binary_search` | 1092 | 1393 | +28 % | 91.600 | 197.251 | +115 % |
| `sort_window` | 1092 | 1394 | +28 % | 72.918 | 183.720 | +152 % |
| `bloom_filter` | 1092 | 1393 | +28 % | 48.061 | 154.500 | +221 % |
| `hash_join` | 1094 | 1396 | +28 % | 67.392 | 179.010 | +166 % |
| `sieve` | 1092 | 1393 | +28 % | 63.647 | 175.974 | +176 % |
| `fib` | 1092 | 1393 | +28 % | 74.640 | 188.876 | +153 % |
| `collatz` | 1092 | 1393 | +28 % | 47.337 | 158.396 | +235 % |
| `matmul` | 1092 | 1393 | +28 % | 58.422 | 165.786 | +184 % |
| `json_parse` | 1118 | 1416 | +27 % | 56.089 | 174.229 | +211 % |
| `nbody` | 1094 | 1395 | +27 % | 88.061 | 187.815 | +113 % |

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
| _(floor: empty program)_ | _2.721_ | _97.216_ | _61.003_ | _58.470_ | _41.626_ | _55.068_ | _68.006_ |
| `lcg` | 2.950 | 106.472 | 62.803 | 69.755 | 42.615 | 62.218 | 76.246 |
| `packet_classifier` | 2.900 | 103.833 | 63.680 | 69.290 | 42.340 | 61.810 | 74.827 |
| `ring_write` | 2.966 | 104.953 | 60.066 | 69.961 | 41.730 | 61.356 | 75.646 |
| `histogram_bins` | 3.040 | 104.245 | 59.333 | 69.750 | 40.563 | 62.813 | 75.563 |
| `prefix_scan` | 3.078 | 105.690 | 58.944 | 71.570 | 40.896 | 63.066 | 77.204 |
| `binary_search` | 3.201 | 105.433 | 59.753 | 68.532 | 41.368 | 65.832 | 79.960 |
| `sort_window` | 3.277 | 115.207 | 62.030 | 75.575 | 42.764 | 71.467 | 84.377 |
| `bloom_filter` | 3.537 | 112.607 | 62.155 | 77.423 | 42.163 | 67.464 | 81.474 |
| `hash_join` | 6.079 | 230.793 | 73.204 | 120.856 | 42.587 | 103.559 | 117.582 |
| `sieve` | 3.101 | 108.231 | 71.633 | 78.578 | 42.215 | 69.760 | 82.899 |
| `fib` | 2.853 | 101.930 | 59.260 | 67.924 | 42.563 | 60.178 | 74.264 |
| `collatz` | 2.999 | 101.588 | 59.258 | 67.027 | 41.763 | 62.333 | 76.256 |
| `matmul` | 3.377 | 111.358 | 63.602 | 81.184 | 42.003 | 84.584 | 95.169 |
| `json_parse` | 52.462 | 608.932 | 146.613 | 123.611 | 42.933 | 165.235 | 149.087 |
| `nbody` | 4.676 | 123.595 | 67.856 | 96.195 | 41.232 | 84.987 | 97.943 |

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
