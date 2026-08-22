# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-22T03:26:19Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `812bbd718cd9d3d67dd6e09693756bb8342ee613` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32548591514 |
| NURL | `v0.48.0-3-g812bbd71` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.7), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.9.0 (pure NURL)) — interpreter, built from this repo |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | yes |
| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |

## 1. What wasm costs — native vs the same module on a JIT

Whole-process wall clock in milliseconds, start-up included. The `x`
columns are wasm ÷ native for that language: how much slower the *same
source* got by being compiled to wasm and run under a JIT instead of
straight to the machine. Because all three languages appear, the column
answers a question a NURL-only table could not: whether a gap belongs to
NURL's wasm pipeline or to wasm itself.

| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.448_ | _10.772_ | _7.4_ | _1.528_ | _6.903_ | _4.5_ | _1.619_ | _33.584_ | _20.7_ |
| `lcg` | 39.010 | 66.387 | 1.7 | 39.077 | 65.474 | 1.7 | 39.180 | 73.581 | 1.9 |
| `packet_classifier` | 56.099 | 80.461 | 1.4 | 56.164 | 79.308 | 1.4 | 56.264 | 88.079 | 1.6 |
| `ring_write` | 42.037 | 79.854 | 1.9 | 42.133 | 78.612 | 1.9 | 42.342 | 87.769 | 2.1 |
| `histogram_bins` | 39.458 | 78.981 | 2.0 | 41.084 | 75.011 | 1.8 | 41.265 | 84.252 | 2.0 |
| `prefix_scan` | 21.668 | 40.403 | 1.9 | 21.814 | 37.714 | 1.7 | 21.873 | 48.738 | 2.2 |
| `binary_search` | 39.835 | 90.974 | 2.3 | 38.211 | 90.382 | 2.4 | 38.271 | 97.976 | 2.6 |
| `sort_window` | 27.273 | 73.144 | 2.7 | 27.330 | 61.027 | 2.2 | 26.848 | 69.908 | 2.6 |
| `bloom_filter` | 17.496 | 45.290 | 2.6 | 18.025 | 44.794 | 2.5 | 18.287 | 52.507 | 2.9 |
| `hash_join` | 27.845 | 71.373 | 2.6 | 29.951 | 76.936 | 2.6 | 29.811 | 82.404 | 2.8 |
| `sieve` | 18.005 | 56.606 | 3.1 | 17.781 | 59.071 | 3.3 | 17.943 | 56.977 | 3.2 |
| `fib` | 25.038 | 75.833 | 3.0 | 29.790 | 70.189 | 2.4 | 25.283 | 77.875 | 3.1 |
| `collatz` | 12.228 | 46.569 | 3.8 | 12.292 | 45.691 | 3.7 | 12.313 | 53.131 | 4.3 |
| `matmul` | 33.330 | 56.663 | 1.7 | 33.308 | 53.478 | 1.6 | 33.479 | 62.498 | 1.9 |
| `json_parse` | 8.878 | 54.609 | 6.2 | 8.574 | 40.992 | 4.8 | 11.525 | 58.203 | 5.1 |
| `nbody` | 40.642 | 76.713 | 1.9 | 40.555 | 73.369 | 1.8 | 38.802 | 79.590 | 2.1 |

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
| `lcg` | 1.5 | — | 1.6 | 1.1 |
| `packet_classifier` | 1.3 | — | 1.3 | 1.0 |
| `ring_write` | 1.7 | — | 1.8 | 1.3 |
| `histogram_bins` | 1.8 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.5 | — | 1.5 | — |
| `binary_search` | 2.1 | — | 2.3 | 1.8 |
| `sort_window` | 2.4 | — | 2.1 | 1.4 |
| `bloom_filter` | 2.2 | — | 2.3 | — |
| `hash_join` | 2.3 | — | 2.5 | 1.7 |
| `sieve` | 2.8 | — | 3.2 | — |
| `fib` | 2.8 | — | 2.2 | 1.9 |
| `collatz` | 3.3 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.5 | — |
| `json_parse` | 5.9 | — | 4.8 | — |
| `nbody` | 1.7 | — | 1.7 | 1.2 |

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
| _(floor: empty program)_ | _38.429_ | _3.6_ | _26.5_ | _38.386_ | _5.364_ |
| `lcg` | 657.964 | 9.9 | 16.9 | 667.346 | 633.895 |
| `packet_classifier` | 1409.246 | 17.5 | 25.1 | 1330.283 | 1404.927 |
| `ring_write` | 1556.400 | 19.5 | 37.0 | 1491.540 | 1502.222 |
| `histogram_bins` | 2280.050 | 28.9 | 57.8 | 2118.894 | 2239.020 |
| `prefix_scan` | 633.195 | 15.7 | 29.2 | 476.122 | 592.854 |
| `binary_search` | 3697.318 | 40.6 | 92.8 | 3323.072 | 3488.140 |
| `sort_window` | 2788.892 | 38.1 | 102.3 | 1852.499 | 1854.166 |
| `bloom_filter` | 1081.790 | 23.9 | 61.8 | 1231.191 | 1120.840 |
| `hash_join` | 3378.142 | 47.3 | 121.3 | 3439.868 | 3394.146 |
| `sieve` | 1595.939 | 28.2 | 88.6 | 1614.260 | 1113.334 |
| `fib` | 1427.264 | 18.8 | 57.0 | 1260.476 | 1142.939 |
| `collatz` | 666.885 | 14.3 | 54.5 | 659.147 | 623.927 |
| `matmul` | 932.912 | 16.5 | 28.0 | 977.586 | 952.820 |
| `json_parse` | 868.198 | 15.9 | 97.8 | 399.946 | 530.460 |
| `nbody` | 5170.694 | 67.4 | 127.2 | 5102.565 | 5011.392 |

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
| `lcg` | 16 | 1086 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 16 | 1085 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1086 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1086 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1086 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1086 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1086 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1086 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1088 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1086 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1085 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1085 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1086 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1111 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1087 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1066_ | _1384_ | _+30 %_ | _10.772_ | _136.570_ | _+1168 %_ |
| `lcg` | 1086 | 1385 | +28 % | 66.387 | 174.810 | +163 % |
| `packet_classifier` | 1085 | 1384 | +28 % | 80.461 | 187.202 | +133 % |
| `ring_write` | 1086 | 1385 | +28 % | 79.854 | 187.198 | +134 % |
| `histogram_bins` | 1086 | 1385 | +28 % | 78.981 | 190.567 | +141 % |
| `prefix_scan` | 1086 | 1385 | +28 % | 40.403 | 149.633 | +270 % |
| `binary_search` | 1086 | 1384 | +28 % | 90.974 | 198.991 | +119 % |
| `sort_window` | 1086 | 1385 | +28 % | 73.144 | 181.238 | +148 % |
| `bloom_filter` | 1086 | 1385 | +28 % | 45.290 | 152.355 | +236 % |
| `hash_join` | 1088 | 1387 | +28 % | 71.373 | 174.326 | +144 % |
| `sieve` | 1086 | 1385 | +28 % | 56.606 | 170.155 | +201 % |
| `fib` | 1085 | 1384 | +28 % | 75.833 | 177.543 | +134 % |
| `collatz` | 1085 | 1384 | +28 % | 46.569 | 154.629 | +232 % |
| `matmul` | 1086 | 1385 | +28 % | 56.663 | 166.166 | +193 % |
| `json_parse` | 1111 | 1407 | +27 % | 54.609 | 167.297 | +206 % |
| `nbody` | 1087 | 1386 | +27 % | 76.713 | 186.627 | +143 % |

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
| _(floor: empty program)_ | _2.702_ | _93.905_ | _75.175_ | _56.063_ | _39.789_ | _55.085_ | _67.127_ |
| `lcg` | 2.750 | 97.144 | 75.860 | 65.493 | 39.679 | 59.550 | 73.306 |
| `packet_classifier` | 2.882 | 100.501 | 76.992 | 66.402 | 41.318 | 60.538 | 73.768 |
| `ring_write` | 3.040 | 103.498 | 79.188 | 69.458 | 42.435 | 61.386 | 76.184 |
| `histogram_bins` | 3.024 | 102.533 | 79.080 | 69.306 | 40.424 | 62.565 | 76.395 |
| `prefix_scan` | 3.142 | 105.352 | 81.651 | 70.814 | 40.962 | 63.590 | 78.431 |
| `binary_search` | 3.242 | 102.546 | 80.882 | 68.001 | 40.354 | 65.643 | 79.640 |
| `sort_window` | 3.308 | 111.875 | 83.907 | 76.187 | 40.305 | 70.257 | 83.750 |
| `bloom_filter` | 3.505 | 107.792 | 82.850 | 74.837 | 40.428 | 66.439 | 78.611 |
| `hash_join` | 6.077 | 223.451 | 112.235 | 119.032 | 40.977 | 99.941 | 114.994 |
| `sieve` | 3.145 | 103.287 | 79.356 | 76.419 | 40.705 | 69.701 | 81.489 |
| `fib` | 2.825 | 94.973 | 74.240 | 64.449 | 40.699 | 58.662 | 72.923 |
| `collatz` | 3.023 | 99.660 | 77.900 | 65.389 | 39.990 | 61.487 | 74.651 |
| `matmul` | 3.393 | 107.934 | 84.068 | 77.748 | 41.217 | 82.496 | 91.747 |
| `json_parse` | 52.201 | 596.452 | 297.084 | 119.603 | 40.748 | 163.088 | 146.652 |
| `nbody` | 4.748 | 119.906 | 114.536 | 94.182 | 40.441 | 84.875 | 96.768 |

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
