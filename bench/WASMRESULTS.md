# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-23T17:04:29Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `6378587a9b50aff6a98c4cc2dcc3dd682034df81` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32653425470 |
| NURL | `v0.50.0-1-g6378587a` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.0), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.14.0 (pure NURL)) — interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.227_ | _8.772_ | _7.1_ | _1.245_ | _5.425_ | _4.4_ | _1.364_ | _31.216_ | _22.9_ |
| `lcg` | 34.162 | 57.354 | 1.7 | 34.247 | 56.551 | 1.7 | 34.266 | 62.732 | 1.8 |
| `packet_classifier` | 49.190 | 69.372 | 1.4 | 49.300 | 67.651 | 1.4 | 49.320 | 74.048 | 1.5 |
| `ring_write` | 36.931 | 67.825 | 1.8 | 36.982 | 66.892 | 1.8 | 37.001 | 71.739 | 1.9 |
| `histogram_bins` | 34.556 | 66.284 | 1.9 | 34.612 | 65.279 | 1.9 | 34.758 | 69.708 | 2.0 |
| `prefix_scan` | 18.938 | 33.653 | 1.8 | 18.992 | 30.700 | 1.6 | 19.059 | 35.759 | 1.9 |
| `binary_search` | 27.395 | 77.293 | 2.8 | 27.730 | 73.878 | 2.7 | 31.720 | 78.409 | 2.5 |
| `sort_window` | 23.737 | 57.831 | 2.4 | 23.826 | 50.126 | 2.1 | 23.349 | 54.799 | 2.3 |
| `bloom_filter` | 15.180 | 38.778 | 2.6 | 15.721 | 38.135 | 2.4 | 15.973 | 42.317 | 2.6 |
| `hash_join` | 22.565 | 55.311 | 2.5 | 23.718 | 57.648 | 2.4 | 24.067 | 64.950 | 2.7 |
| `sieve` | 15.749 | 46.410 | 2.9 | 15.566 | 48.728 | 3.1 | 15.569 | 47.687 | 3.1 |
| `fib` | 21.619 | 57.485 | 2.7 | 25.780 | 59.907 | 2.3 | 21.716 | 63.982 | 2.9 |
| `collatz` | 10.682 | 38.757 | 3.6 | 10.617 | 37.350 | 3.5 | 10.710 | 44.720 | 4.2 |
| `matmul` | 34.803 | 52.592 | 1.5 | 35.199 | 43.855 | 1.2 | 35.296 | 50.578 | 1.4 |
| `json_parse` | 6.711 | 41.549 | 6.2 | 7.059 | 29.993 | 4.2 | 9.326 | 44.746 | 4.8 |
| `nbody` | 35.708 | 59.697 | 1.7 | 35.809 | 58.344 | 1.6 | 34.032 | 67.066 | 2.0 |

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
| `lcg` | 1.5 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.3 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.7 | 1.1 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.4 | — |
| `binary_search` | 2.6 | — | 2.6 | 1.6 |
| `sort_window` | 2.2 | — | 2.0 | — |
| `bloom_filter` | 2.2 | — | 2.3 | — |
| `hash_join` | 2.2 | — | 2.3 | 1.5 |
| `sieve` | 2.6 | — | 3.0 | — |
| `fib` | 2.4 | — | 2.2 | 1.6 |
| `collatz` | 3.2 | — | 3.4 | — |
| `matmul` | 1.3 | — | 1.1 | — |
| `json_parse` | 6.0 | — | 4.2 | — |
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
| _(floor: empty program)_ | _1.855_ | _0.2_ | _1.5_ | _1.834_ | _1.939_ |
| `lcg` | 179.328 | 3.1 | 5.2 | 166.663 | 178.111 |
| `packet_classifier` | 357.374 | 5.2 | 7.3 | 269.793 | 302.943 |
| `ring_write` | 368.395 | 5.4 | 10.0 | 328.839 | 330.088 |
| `histogram_bins` | 510.414 | 7.7 | 14.8 | 471.090 | 463.975 |
| `prefix_scan` | 130.510 | 3.9 | 6.9 | 108.369 | 116.733 |
| `binary_search` | 875.495 | 11.3 | 32.0 | 842.121 | 942.129 |
| `sort_window` | 730.386 | 12.6 | 30.8 | 407.112 | 411.632 |
| `bloom_filter` | 276.527 | 7.1 | 18.2 | 280.499 | 265.389 |
| `hash_join` | 900.257 | 16.3 | 39.9 | 995.438 | 999.976 |
| `sieve` | 418.331 | 9.0 | 26.6 | 425.690 | 322.834 |
| `fib` | 570.539 | 9.9 | 26.4 | 554.430 | 541.524 |
| `collatz` | 164.483 | 4.2 | 15.4 | 135.209 | 142.178 |
| `matmul` | 241.119 | 4.6 | 6.9 | 251.262 | 236.165 |
| `json_parse` | 286.468 | 6.9 | 42.7 | 127.417 | 221.841 |
| `nbody` | 667.120 | 11.2 | 18.7 | 645.806 | 738.055 |

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
| `packet_classifier` | 16 | 1091 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1092 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1092 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1092 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1092 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1092 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1092 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1094 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1092 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1091 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1091 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1092 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1117 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1093 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1072_ | _1392_ | _+30 %_ | _8.772_ | _103.000_ | _+1074 %_ |
| `lcg` | 1092 | 1392 | +28 % | 57.354 | 137.702 | +140 % |
| `packet_classifier` | 1091 | 1392 | +28 % | 69.372 | 149.009 | +115 % |
| `ring_write` | 1092 | 1392 | +28 % | 67.825 | 147.854 | +118 % |
| `histogram_bins` | 1092 | 1392 | +28 % | 66.284 | 150.001 | +126 % |
| `prefix_scan` | 1092 | 1392 | +28 % | 33.653 | 111.915 | +233 % |
| `binary_search` | 1092 | 1392 | +28 % | 77.293 | 153.979 | +99 % |
| `sort_window` | 1092 | 1393 | +28 % | 57.831 | 142.675 | +147 % |
| `bloom_filter` | 1092 | 1393 | +28 % | 38.778 | 121.992 | +215 % |
| `hash_join` | 1094 | 1395 | +28 % | 55.311 | 139.752 | +153 % |
| `sieve` | 1092 | 1392 | +28 % | 46.410 | 133.023 | +187 % |
| `fib` | 1091 | 1392 | +28 % | 57.485 | 142.570 | +148 % |
| `collatz` | 1091 | 1392 | +28 % | 38.757 | 119.587 | +209 % |
| `matmul` | 1092 | 1392 | +28 % | 52.592 | 132.833 | +153 % |
| `json_parse` | 1117 | 1415 | +27 % | 41.549 | 122.585 | +195 % |
| `nbody` | 1093 | 1394 | +27 % | 59.697 | 141.237 | +137 % |

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
| _(floor: empty program)_ | _2.693_ | _81.322_ | _49.705_ | _52.751_ | _34.352_ | _48.057_ | _58.538_ |
| `lcg` | 2.691 | 91.267 | 50.543 | 60.924 | 36.313 | 54.990 | 69.565 |
| `packet_classifier` | 2.534 | 87.103 | 49.186 | 60.314 | 36.262 | 52.933 | 63.717 |
| `ring_write` | 2.640 | 89.048 | 50.579 | 60.116 | 35.499 | 53.454 | 63.787 |
| `histogram_bins` | 2.708 | 90.688 | 50.505 | 61.428 | 36.140 | 55.442 | 65.370 |
| `prefix_scan` | 2.705 | 91.234 | 51.752 | 62.433 | 36.038 | 54.916 | 66.476 |
| `binary_search` | 2.818 | 90.973 | 50.641 | 61.556 | 35.767 | 57.712 | 67.972 |
| `sort_window` | 2.866 | 96.438 | 50.662 | 65.171 | 35.346 | 60.766 | 70.451 |
| `bloom_filter` | 3.074 | 94.773 | 52.464 | 66.420 | 34.478 | 58.810 | 67.519 |
| `hash_join` | 4.966 | 180.523 | 57.885 | 97.619 | 35.866 | 85.325 | 95.703 |
| `sieve` | 2.744 | 92.495 | 50.403 | 68.759 | 56.257 | 61.726 | 70.142 |
| `fib` | 2.541 | 86.584 | 48.815 | 59.004 | 35.573 | 52.273 | 62.709 |
| `collatz` | 2.626 | 89.452 | 49.246 | 59.389 | 36.471 | 54.317 | 64.871 |
| `matmul` | 2.935 | 95.253 | 51.540 | 68.598 | 35.302 | 71.476 | 78.506 |
| `json_parse` | 40.049 | 453.264 | 129.791 | 99.296 | 36.293 | 136.142 | 122.874 |
| `nbody` | 3.910 | 103.474 | 57.792 | 79.454 | 38.693 | 71.769 | 81.824 |

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
