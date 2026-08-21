# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-21T12:51:13Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `a8c3d5ebf98fc01fac568ff515489178c7672a2a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32483482204 |
| NURL | `v0.47.0-12-ga8c3d5eb` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.7), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.8.2 (pure NURL)) — interpreter, built from this repo |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | no (add --wt-all-langs) |
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
| _(floor: empty program)_ | _1.554_ | _12.976_ | _8.4_ | _1.618_ | _7.815_ | _4.8_ | _1.780_ | _33.833_ | _19.0_ |
| `lcg` | 44.199 | 72.666 | 1.6 | 44.210 | 71.150 | 1.6 | 44.453 | 78.359 | 1.8 |
| `packet_classifier` | 63.527 | 89.043 | 1.4 | 63.674 | 87.631 | 1.4 | 63.861 | 92.648 | 1.5 |
| `ring_write` | 47.661 | 87.319 | 1.8 | 47.753 | 85.984 | 1.8 | 47.860 | 92.126 | 1.9 |
| `histogram_bins` | 44.693 | 85.196 | 1.9 | 44.698 | 83.075 | 1.9 | 44.919 | 90.099 | 2.0 |
| `prefix_scan` | 24.638 | 42.994 | 1.7 | 24.646 | 40.669 | 1.7 | 24.813 | 45.919 | 1.9 |
| `binary_search` | 35.963 | 98.179 | 2.7 | 35.767 | 96.701 | 2.7 | 41.162 | 102.461 | 2.5 |
| `sort_window` | 30.763 | 73.997 | 2.4 | 30.897 | 65.139 | 2.1 | 30.375 | 74.392 | 2.4 |
| `bloom_filter` | 19.850 | 52.209 | 2.6 | 20.546 | 47.293 | 2.3 | 20.936 | 54.664 | 2.6 |
| `hash_join` | 29.312 | 72.491 | 2.5 | 30.807 | 74.204 | 2.4 | 31.340 | 87.209 | 2.8 |
| `sieve` | 20.369 | 57.488 | 2.8 | 20.216 | 60.956 | 3.0 | 20.235 | 61.380 | 3.0 |
| `fib` | 27.946 | 73.722 | 2.6 | 33.265 | 73.378 | 2.2 | 28.088 | 84.898 | 3.0 |
| `collatz` | 13.718 | 50.111 | 3.7 | 13.687 | 48.727 | 3.6 | 13.846 | 54.159 | 3.9 |
| `matmul` | 45.972 | 68.753 | 1.5 | 46.298 | 55.093 | 1.2 | 46.954 | 66.072 | 1.4 |
| `json_parse` | 8.637 | 53.692 | 6.2 | 8.885 | 39.096 | 4.4 | 11.934 | 56.957 | 4.8 |
| `nbody` | 46.115 | 79.093 | 1.7 | 46.145 | 73.112 | 1.6 | 43.947 | 80.623 | 1.8 |

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
| `lcg` | 1.4 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.6 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.4 | — |
| `binary_search` | 2.5 | — | 2.6 | 1.7 |
| `sort_window` | 2.1 | — | 2.0 | 1.4 |
| `bloom_filter` | 2.1 | — | 2.1 | — |
| `hash_join` | 2.1 | — | 2.3 | 1.8 |
| `sieve` | 2.4 | — | 2.9 | — |
| `fib` | 2.3 | — | 2.1 | 1.9 |
| `collatz` | 3.1 | — | 3.4 | — |
| `matmul` | 1.3 | — | 1.1 | — |
| `json_parse` | 5.7 | — | 4.3 | — |
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
| _(floor: empty program)_ | _24.639_ | _1.9_ | _15.9_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 929.757 | 12.8 | 21.0 | SKIPPED | SKIPPED |
| `packet_classifier` | 2119.652 | 23.8 | 33.4 | SKIPPED | SKIPPED |
| `ring_write` | 2384.288 | 27.3 | 50.0 | SKIPPED | SKIPPED |
| `histogram_bins` | 2886.684 | 33.9 | 64.6 | SKIPPED | SKIPPED |
| `prefix_scan` | 638.005 | 14.8 | 25.9 | SKIPPED | SKIPPED |
| `binary_search` | 5425.594 | 55.3 | 150.9 | SKIPPED | SKIPPED |
| `sort_window` | 5001.830 | 67.6 | 162.6 | SKIPPED | SKIPPED |
| `bloom_filter` | 1551.551 | 29.7 | 78.2 | SKIPPED | SKIPPED |
| `hash_join` | 4564.686 | 63.0 | 155.7 | SKIPPED | SKIPPED |
| `sieve` | 2687.910 | 46.8 | 132.0 | SKIPPED | SKIPPED |
| `fib` | 2172.374 | 29.5 | 77.7 | SKIPPED | SKIPPED |
| `collatz` | 1010.669 | 20.2 | 73.7 | SKIPPED | SKIPPED |
| `matmul` | 1371.310 | 19.9 | 29.8 | SKIPPED | SKIPPED |
| `json_parse` | 1260.250 | 23.5 | 145.9 | SKIPPED | SKIPPED |
| `nbody` | 6277.100 | 79.4 | 136.1 | SKIPPED | SKIPPED |

The C and Rust columns are `SKIPPED`: they are the cross-frontend
control — modules this runtime never saw during development, from two
other LLVM frontends — and running them costs about three times the
whole rest of the suite, so they are opt-in. `--wt-all-langs` fills
them in. Until it is run, this section says what the interpreter does
with NURL output and nothing about whether it is tuned for it.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 16 | 1086 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 16 | 1086 | 16 | 915 | 4403 | 2084 |
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
| _(floor: empty program)_ | _1066_ | _1384_ | _+30 %_ | _12.976_ | _143.119_ | _+1003 %_ |
| `lcg` | 1086 | 1385 | +28 % | 72.666 | 181.693 | +150 % |
| `packet_classifier` | 1086 | 1384 | +28 % | 89.043 | 193.200 | +117 % |
| `ring_write` | 1086 | 1385 | +28 % | 87.319 | 191.999 | +120 % |
| `histogram_bins` | 1086 | 1385 | +28 % | 85.196 | 200.385 | +135 % |
| `prefix_scan` | 1086 | 1385 | +28 % | 42.994 | 144.521 | +236 % |
| `binary_search` | 1086 | 1384 | +28 % | 98.179 | 199.427 | +103 % |
| `sort_window` | 1086 | 1385 | +28 % | 73.997 | 175.106 | +137 % |
| `bloom_filter` | 1086 | 1385 | +28 % | 52.209 | 157.463 | +202 % |
| `hash_join` | 1088 | 1387 | +28 % | 72.491 | 178.651 | +146 % |
| `sieve` | 1086 | 1385 | +28 % | 57.488 | 164.062 | +185 % |
| `fib` | 1085 | 1384 | +28 % | 73.722 | 179.370 | +143 % |
| `collatz` | 1085 | 1384 | +28 % | 50.111 | 154.374 | +208 % |
| `matmul` | 1086 | 1385 | +28 % | 68.753 | 169.633 | +147 % |
| `json_parse` | 1111 | 1407 | +27 % | 53.692 | 161.220 | +200 % |
| `nbody` | 1087 | 1386 | +27 % | 79.093 | 192.633 | +144 % |

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
| _(floor: empty program)_ | _2.929_ | _105.219_ | _83.464_ | _67.382_ | _45.659_ | _60.571_ | _73.732_ |
| `lcg` | 3.182 | 112.808 | 84.967 | 75.847 | 46.578 | 66.605 | 81.135 |
| `packet_classifier` | 3.251 | 115.802 | 86.771 | 77.407 | 46.402 | 66.725 | 78.876 |
| `ring_write` | 3.318 | 114.696 | 87.601 | 76.420 | 45.870 | 67.107 | 80.843 |
| `histogram_bins` | 3.432 | 119.827 | 89.643 | 80.605 | 46.923 | 69.805 | 82.087 |
| `prefix_scan` | 3.457 | 120.835 | 94.225 | 81.066 | 46.185 | 69.325 | 83.529 |
| `binary_search` | 3.611 | 116.782 | 90.553 | 76.870 | 46.993 | 72.326 | 86.133 |
| `sort_window` | 3.724 | 126.026 | 93.107 | 83.092 | 46.544 | 75.656 | 90.110 |
| `bloom_filter` | 3.939 | 124.722 | 95.008 | 85.217 | 46.838 | 72.689 | 86.629 |
| `hash_join` | 6.389 | 230.566 | 124.046 | 123.015 | 47.714 | 106.001 | 120.695 |
| `sieve` | 3.454 | 118.463 | 88.916 | 85.101 | 45.477 | 75.817 | 87.377 |
| `fib` | 3.188 | 109.555 | 82.184 | 73.239 | 44.599 | 63.559 | 76.349 |
| `collatz` | 3.328 | 115.160 | 87.824 | 75.221 | 45.951 | 67.523 | 82.654 |
| `matmul` | 3.688 | 119.533 | 94.734 | 86.613 | 45.222 | 88.000 | 97.015 |
| `json_parse` | 52.280 | 584.927 | 325.538 | 126.114 | 46.008 | 174.047 | 153.933 |
| `nbody` | 5.048 | 130.119 | 127.053 | 100.021 | 45.922 | 89.099 | 101.432 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |

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
