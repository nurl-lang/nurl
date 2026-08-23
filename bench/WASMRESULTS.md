# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-23T00:25:26Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `11e7e8af283c2c50123debc286c965c67e62e289` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32607567166 |
| NURL | `v0.49.0-9-g11e7e8af` |
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
| _(floor: empty program)_ | _1.576_ | _11.398_ | _7.2_ | _1.628_ | _7.640_ | _4.7_ | _1.776_ | _37.728_ | _21.2_ |
| `lcg` | 44.078 | 71.555 | 1.6 | 44.049 | 70.283 | 1.6 | 44.174 | 77.814 | 1.8 |
| `packet_classifier` | 63.440 | 87.365 | 1.4 | 63.544 | 87.491 | 1.4 | 63.768 | 94.250 | 1.5 |
| `ring_write` | 47.486 | 87.099 | 1.8 | 47.679 | 85.207 | 1.8 | 47.821 | 92.831 | 1.9 |
| `histogram_bins` | 44.582 | 85.703 | 1.9 | 44.701 | 86.086 | 1.9 | 44.799 | 91.498 | 2.0 |
| `prefix_scan` | 24.397 | 43.957 | 1.8 | 24.529 | 41.104 | 1.7 | 24.627 | 47.601 | 1.9 |
| `binary_search` | 35.599 | 96.666 | 2.7 | 35.868 | 95.225 | 2.7 | 41.101 | 101.752 | 2.5 |
| `sort_window` | 30.768 | 74.170 | 2.4 | 30.786 | 64.644 | 2.1 | 30.227 | 69.899 | 2.3 |
| `bloom_filter` | 20.864 | 49.089 | 2.4 | 20.536 | 47.623 | 2.3 | 20.862 | 55.353 | 2.7 |
| `hash_join` | 29.168 | 68.151 | 2.3 | 30.790 | 73.047 | 2.4 | 31.101 | 80.942 | 2.6 |
| `sieve` | 20.296 | 57.263 | 2.8 | 20.016 | 59.466 | 3.0 | 20.103 | 60.320 | 3.0 |
| `fib` | 27.917 | 71.636 | 2.6 | 33.253 | 75.461 | 2.3 | 28.072 | 78.592 | 2.8 |
| `collatz` | 13.690 | 48.942 | 3.6 | 13.673 | 52.501 | 3.8 | 13.897 | 55.842 | 4.0 |
| `matmul` | 45.327 | 67.202 | 1.5 | 45.711 | 57.904 | 1.3 | 45.710 | 67.000 | 1.5 |
| `json_parse` | 8.697 | 50.564 | 5.8 | 8.920 | 39.267 | 4.4 | 12.105 | 56.972 | 4.7 |
| `nbody` | 46.039 | 77.927 | 1.7 | 46.132 | 75.072 | 1.6 | 43.863 | 82.114 | 1.9 |

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
| `lcg` | 1.4 | — | 1.5 | 0.9 |
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.5 | — |
| `binary_search` | 2.5 | — | 2.6 | 1.6 |
| `sort_window` | 2.2 | — | 2.0 | — |
| `bloom_filter` | 2.0 | — | 2.1 | — |
| `hash_join` | 2.1 | — | 2.2 | 1.5 |
| `sieve` | 2.5 | — | 2.8 | — |
| `fib` | 2.3 | — | 2.1 | 1.6 |
| `collatz` | 3.1 | — | 3.7 | — |
| `matmul` | 1.3 | — | 1.1 | — |
| `json_parse` | 5.5 | — | 4.3 | — |
| `nbody` | 1.5 | — | 1.5 | 1.1 |

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
| _(floor: empty program)_ | _2.058_ | _0.2_ | _1.3_ | _2.415_ | _2.180_ |
| `lcg` | 268.754 | 3.8 | 6.1 | 312.438 | 317.374 |
| `packet_classifier` | 512.702 | 5.9 | 8.1 | 474.387 | 514.080 |
| `ring_write` | 562.885 | 6.5 | 11.9 | 542.478 | 522.419 |
| `histogram_bins` | 698.122 | 8.1 | 15.7 | 736.414 | 690.450 |
| `prefix_scan` | 186.162 | 4.2 | 7.6 | 191.406 | 185.970 |
| `binary_search` | 1234.569 | 12.8 | 34.7 | 1183.937 | 1285.567 |
| `sort_window` | 969.188 | 13.1 | 31.5 | 589.266 | 631.040 |
| `bloom_filter` | 368.364 | 7.5 | 17.7 | 402.993 | 361.732 |
| `hash_join` | 1167.885 | 17.1 | 40.0 | 1272.920 | 1292.949 |
| `sieve` | 525.943 | 9.2 | 25.9 | 545.973 | 395.689 |
| `fib` | 777.835 | 10.9 | 27.9 | 764.272 | 712.898 |
| `collatz` | 231.141 | 4.7 | 16.9 | 227.502 | 226.046 |
| `matmul` | 295.079 | 4.4 | 6.5 | 313.098 | 313.553 |
| `json_parse` | 365.082 | 7.2 | 42.0 | 163.681 | 286.070 |
| `nbody` | 892.344 | 11.5 | 19.4 | 909.583 | 956.415 |

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
| _(floor: empty program)_ | _1071_ | _1391_ | _+30 %_ | _11.398_ | _141.476_ | _+1141 %_ |
| `lcg` | 1090 | 1391 | +28 % | 71.555 | 178.610 | +150 % |
| `packet_classifier` | 1090 | 1391 | +28 % | 87.365 | 194.816 | +123 % |
| `ring_write` | 1090 | 1391 | +28 % | 87.099 | 194.137 | +123 % |
| `histogram_bins` | 1091 | 1391 | +28 % | 85.703 | 193.082 | +125 % |
| `prefix_scan` | 1091 | 1391 | +28 % | 43.957 | 143.344 | +226 % |
| `binary_search` | 1091 | 1391 | +28 % | 96.666 | 201.395 | +108 % |
| `sort_window` | 1091 | 1392 | +28 % | 74.170 | 178.326 | +140 % |
| `bloom_filter` | 1091 | 1391 | +28 % | 49.089 | 154.623 | +215 % |
| `hash_join` | 1093 | 1394 | +28 % | 68.151 | 181.266 | +166 % |
| `sieve` | 1090 | 1391 | +28 % | 57.263 | 168.492 | +194 % |
| `fib` | 1090 | 1391 | +28 % | 71.636 | 187.037 | +161 % |
| `collatz` | 1090 | 1391 | +28 % | 48.942 | 153.335 | +213 % |
| `matmul` | 1091 | 1391 | +28 % | 67.202 | 176.029 | +162 % |
| `json_parse` | 1116 | 1414 | +27 % | 50.564 | 159.549 | +216 % |
| `nbody` | 1092 | 1393 | +27 % | 77.927 | 183.391 | +135 % |

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
| _(floor: empty program)_ | _2.949_ | _100.733_ | _61.575_ | _66.663_ | _45.274_ | _59.154_ | _71.970_ |
| `lcg` | 3.136 | 108.060 | 62.142 | 73.688 | 45.372 | 64.459 | 78.327 |
| `packet_classifier` | 3.204 | 111.413 | 63.380 | 75.501 | 46.162 | 64.688 | 80.732 |
| `ring_write` | 3.358 | 111.477 | 63.315 | 84.446 | 45.631 | 66.703 | 79.552 |
| `histogram_bins` | 3.439 | 114.421 | 63.902 | 77.369 | 44.929 | 68.360 | 81.553 |
| `prefix_scan` | 3.427 | 115.682 | 65.461 | 78.584 | 45.848 | 69.491 | 83.334 |
| `binary_search` | 3.640 | 115.063 | 64.606 | 77.470 | 45.889 | 71.445 | 84.644 |
| `sort_window` | 3.684 | 123.756 | 66.566 | 84.309 | 46.445 | 75.889 | 89.961 |
| `bloom_filter` | 3.956 | 124.275 | 67.214 | 85.261 | 48.011 | 73.605 | 86.337 |
| `hash_join` | 6.539 | 231.357 | 72.919 | 123.875 | 45.116 | 105.657 | 135.486 |
| `sieve` | 3.457 | 116.521 | 64.888 | 86.302 | 45.608 | 76.843 | 86.687 |
| `fib` | 3.180 | 108.053 | 63.763 | 75.199 | 45.798 | 64.120 | 78.556 |
| `collatz` | 3.345 | 111.229 | 63.690 | 73.007 | 46.061 | 66.487 | 79.391 |
| `matmul` | 3.736 | 120.563 | 65.268 | 84.706 | 46.157 | 88.619 | 97.343 |
| `json_parse` | 53.088 | 594.624 | 147.718 | 128.509 | 46.065 | 175.047 | 154.881 |
| `nbody` | 5.103 | 131.127 | 71.738 | 101.340 | 45.949 | 89.857 | 102.479 |

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
