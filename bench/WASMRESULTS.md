# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-22T20:35:56Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `bac8be55d304465e3216e09be9ab6f910fefaf1e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32596760051 |
| NURL | `v0.49.0-6-gbac8be55` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.8), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.12.0 (pure NURL)) — interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.444_ | _11.394_ | _7.9_ | _1.475_ | _7.357_ | _5.0_ | _1.640_ | _35.301_ | _21.5_ |
| `lcg` | 39.038 | 66.234 | 1.7 | 39.210 | 67.009 | 1.7 | 39.348 | 74.423 | 1.9 |
| `packet_classifier` | 56.353 | 81.245 | 1.4 | 56.224 | 79.925 | 1.4 | 56.463 | 87.483 | 1.5 |
| `ring_write` | 42.147 | 79.927 | 1.9 | 42.174 | 77.939 | 1.8 | 42.397 | 87.833 | 2.1 |
| `histogram_bins` | 39.533 | 77.344 | 2.0 | 41.157 | 75.870 | 1.8 | 41.381 | 85.482 | 2.1 |
| `prefix_scan` | 21.667 | 39.383 | 1.8 | 21.731 | 38.956 | 1.8 | 21.700 | 46.300 | 2.1 |
| `binary_search` | 39.558 | 90.662 | 2.3 | 38.279 | 90.225 | 2.4 | 38.104 | 99.269 | 2.6 |
| `sort_window` | 27.140 | 76.219 | 2.8 | 27.290 | 59.371 | 2.2 | 26.669 | 68.840 | 2.6 |
| `bloom_filter` | 17.456 | 45.913 | 2.6 | 18.001 | 47.422 | 2.6 | 18.288 | 57.959 | 3.2 |
| `hash_join` | 28.066 | 69.422 | 2.5 | 29.972 | 73.819 | 2.5 | 29.690 | 82.560 | 2.8 |
| `sieve` | 19.891 | 56.795 | 2.9 | 19.955 | 61.129 | 3.1 | 17.897 | 58.430 | 3.3 |
| `fib` | 25.100 | 71.681 | 2.9 | 29.846 | 76.970 | 2.6 | 25.341 | 77.663 | 3.1 |
| `collatz` | 12.274 | 46.597 | 3.8 | 12.227 | 45.928 | 3.8 | 12.394 | 54.080 | 4.4 |
| `matmul` | 33.511 | 57.059 | 1.7 | 33.720 | 51.935 | 1.5 | 33.631 | 61.263 | 1.8 |
| `json_parse` | 8.947 | 50.555 | 5.7 | 8.795 | 44.514 | 5.1 | 11.746 | 59.870 | 5.1 |
| `nbody` | 40.693 | 76.357 | 1.9 | 40.717 | 68.816 | 1.7 | 38.942 | 80.075 | 2.1 |

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
| `packet_classifier` | 1.3 | — | 1.3 | 1.0 |
| `ring_write` | 1.7 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.4 | — | 1.6 | — |
| `binary_search` | 2.1 | — | 2.3 | 1.8 |
| `sort_window` | 2.5 | — | 2.0 | — |
| `bloom_filter` | 2.2 | — | 2.4 | — |
| `hash_join` | 2.2 | — | 2.3 | 1.7 |
| `sieve` | 2.5 | — | 2.9 | — |
| `fib` | 2.5 | — | 2.5 | 1.8 |
| `collatz` | 3.3 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.2 | — | 5.1 | — |
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
| _(floor: empty program)_ | _2.366_ | _0.2_ | _1.6_ | _2.357_ | _2.775_ |
| `lcg` | 263.445 | 4.0 | 6.7 | 322.123 | 321.195 |
| `packet_classifier` | 448.439 | 5.5 | 8.0 | 443.157 | 462.887 |
| `ring_write` | 498.371 | 6.2 | 11.8 | 495.329 | 488.151 |
| `histogram_bins` | 628.948 | 8.1 | 15.9 | 672.758 | 642.006 |
| `prefix_scan` | 177.922 | 4.5 | 8.2 | 186.276 | 179.479 |
| `binary_search` | 1136.847 | 12.5 | 28.7 | 1163.028 | 1230.376 |
| `sort_window` | 833.928 | 10.9 | 30.7 | 520.865 | 549.622 |
| `bloom_filter` | 330.922 | 7.2 | 19.0 | 370.675 | 333.186 |
| `hash_join` | 1070.025 | 15.4 | 38.1 | 1209.506 | 1219.330 |
| `sieve` | 529.148 | 9.3 | 26.6 | 536.079 | 405.514 |
| `fib` | 816.292 | 11.4 | 32.5 | 787.417 | 762.251 |
| `collatz` | 221.083 | 4.7 | 18.0 | 221.418 | 220.809 |
| `matmul` | 276.290 | 4.8 | 8.2 | 290.219 | 294.227 |
| `json_parse` | 403.703 | 8.0 | 45.1 | 160.292 | 287.077 |
| `nbody` | 833.763 | 10.9 | 20.5 | 829.720 | 894.457 |

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
| `lcg` | 16 | 1090 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 16 | 1090 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1090 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1091 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1091 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1091 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1091 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1091 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1093 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1090 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1090 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1090 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1091 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1116 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1092 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1071_ | _1391_ | _+30 %_ | _11.394_ | _144.233_ | _+1166 %_ |
| `lcg` | 1090 | 1391 | +28 % | 66.234 | 174.737 | +164 % |
| `packet_classifier` | 1090 | 1391 | +28 % | 81.245 | 190.471 | +134 % |
| `ring_write` | 1090 | 1391 | +28 % | 79.927 | 187.014 | +134 % |
| `histogram_bins` | 1091 | 1391 | +28 % | 77.344 | 190.429 | +146 % |
| `prefix_scan` | 1091 | 1391 | +28 % | 39.383 | 152.726 | +288 % |
| `binary_search` | 1091 | 1391 | +28 % | 90.662 | 196.674 | +117 % |
| `sort_window` | 1091 | 1392 | +28 % | 76.219 | 179.826 | +136 % |
| `bloom_filter` | 1091 | 1391 | +28 % | 45.913 | 160.607 | +250 % |
| `hash_join` | 1093 | 1394 | +28 % | 69.422 | 184.362 | +166 % |
| `sieve` | 1090 | 1391 | +28 % | 56.795 | 168.449 | +197 % |
| `fib` | 1090 | 1391 | +28 % | 71.681 | 179.237 | +150 % |
| `collatz` | 1090 | 1391 | +28 % | 46.597 | 155.077 | +233 % |
| `matmul` | 1091 | 1391 | +28 % | 57.059 | 167.969 | +194 % |
| `json_parse` | 1116 | 1414 | +27 % | 50.555 | 167.171 | +231 % |
| `nbody` | 1092 | 1393 | +27 % | 76.357 | 192.720 | +152 % |

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
| _(floor: empty program)_ | _2.660_ | _91.398_ | _1722.437_ | _56.459_ | _40.421_ | _54.406_ | _66.787_ |
| `lcg` | 2.829 | 97.875 | 1644.060 | 64.911 | 41.296 | 59.243 | 73.274 |
| `packet_classifier` | 2.922 | 100.721 | 1666.347 | 66.308 | 40.714 | 60.239 | 73.463 |
| `ring_write` | 2.997 | 101.956 | 1619.640 | 68.221 | 41.402 | 61.598 | 75.233 |
| `histogram_bins` | 3.070 | 102.173 | 1641.498 | 69.014 | 41.070 | 62.495 | 75.931 |
| `prefix_scan` | 3.119 | 105.774 | 1543.627 | 71.956 | 41.742 | 63.491 | 80.403 |
| `binary_search` | 3.376 | 106.229 | 1616.868 | 69.252 | 40.733 | 65.370 | 78.669 |
| `sort_window` | 3.310 | 110.425 | 1586.889 | 74.805 | 41.300 | 69.985 | 83.244 |
| `bloom_filter` | 3.511 | 110.437 | 1681.355 | 76.347 | 42.308 | 67.096 | 79.339 |
| `hash_join` | 5.981 | 230.637 | 1653.899 | 120.734 | 40.749 | 103.679 | 114.659 |
| `sieve` | 3.108 | 105.049 | 1563.347 | 77.338 | 41.259 | 69.973 | 81.812 |
| `fib` | 2.813 | 99.200 | 1584.598 | 67.632 | 41.198 | 58.998 | 72.954 |
| `collatz` | 2.975 | 101.900 | 1590.347 | 66.782 | 42.090 | 62.101 | 75.149 |
| `matmul` | 3.405 | 110.133 | 1614.631 | 81.389 | 41.352 | 84.850 | 92.763 |
| `json_parse` | 52.148 | 610.566 | 1763.141 | 124.593 | 44.066 | 167.423 | 152.417 |
| `nbody` | 4.682 | 124.646 | 1632.285 | 97.624 | 41.906 | 85.563 | 97.751 |

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
