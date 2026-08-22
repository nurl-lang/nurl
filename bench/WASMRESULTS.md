# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-22T16:56:09Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `1c6ef287d1269ff973930368e903a885b40d7a38` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32585981959 |
| NURL | `v0.49.0-2-g1c6ef287` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.7), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.11.0 (pure NURL)) — interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.228_ | _8.542_ | _7.0_ | _1.197_ | _6.045_ | _5.1_ | _1.278_ | _28.499_ | _22.3_ |
| `lcg` | 31.728 | 50.846 | 1.6 | 31.675 | 50.414 | 1.6 | 31.570 | 56.805 | 1.8 |
| `packet_classifier` | 56.809 | 66.510 | 1.2 | 61.026 | 64.540 | 1.1 | 59.910 | 67.756 | 1.1 |
| `ring_write` | 34.282 | 62.579 | 1.8 | 34.994 | 68.057 | 1.9 | 33.811 | 68.086 | 2.0 |
| `histogram_bins` | 36.282 | 65.369 | 1.8 | 37.548 | 66.811 | 1.8 | 36.053 | 71.512 | 2.0 |
| `prefix_scan` | 19.646 | 31.529 | 1.6 | 19.886 | 27.580 | 1.4 | 19.698 | 33.339 | 1.7 |
| `binary_search` | 27.344 | 69.618 | 2.5 | 24.384 | 65.559 | 2.7 | 25.397 | 82.048 | 3.2 |
| `sort_window` | 33.003 | 55.134 | 1.7 | 41.304 | 49.331 | 1.2 | 35.847 | 52.235 | 1.5 |
| `bloom_filter` | 10.972 | 33.109 | 3.0 | 11.278 | 29.693 | 2.6 | 11.434 | 35.333 | 3.1 |
| `hash_join` | 22.638 | 53.282 | 2.4 | 22.951 | 61.167 | 2.7 | 22.543 | 63.382 | 2.8 |
| `sieve` | 34.557 | 61.737 | 1.8 | 33.575 | 57.450 | 1.7 | 33.553 | 67.651 | 2.0 |
| `fib` | 18.277 | 56.378 | 3.1 | 21.175 | 45.518 | 2.1 | 19.285 | 57.041 | 3.0 |
| `collatz` | 11.783 | 35.935 | 3.0 | 12.043 | 33.899 | 2.8 | 12.803 | 39.681 | 3.1 |
| `matmul` | 15.777 | 40.374 | 2.6 | 15.495 | 35.937 | 2.3 | 17.639 | 42.272 | 2.4 |
| `json_parse` | 5.939 | 33.776 | 5.7 | 6.059 | 27.842 | 4.6 | 7.308 | 40.241 | 5.5 |
| `nbody` | 24.290 | 46.747 | 1.9 | 24.361 | 43.103 | 1.8 | 22.433 | 54.332 | 2.4 |

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
| `lcg` | 1.4 | — | 1.5 | — |
| `packet_classifier` | 1.0 | — | 1.0 | 0.7 |
| `ring_write` | 1.6 | — | 1.8 | 1.2 |
| `histogram_bins` | 1.6 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.2 | — | 1.2 | — |
| `binary_search` | 2.3 | — | 2.6 | 2.2 |
| `sort_window` | 1.5 | — | 1.1 | — |
| `bloom_filter` | 2.5 | — | 2.3 | — |
| `hash_join` | 2.1 | — | 2.5 | 1.6 |
| `sieve` | 1.6 | — | 1.6 | 1.2 |
| `fib` | 2.8 | — | 2.0 | 1.6 |
| `collatz` | 2.6 | — | 2.6 | — |
| `matmul` | 2.2 | — | 2.1 | — |
| `json_parse` | 5.4 | — | 4.5 | — |
| `nbody` | 1.7 | — | 1.6 | — |

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
| _(floor: empty program)_ | _1.792_ | _0.2_ | _1.5_ | _1.660_ | _1.765_ |
| `lcg` | 156.854 | 3.1 | 4.9 | 160.840 | 169.793 |
| `packet_classifier` | 355.899 | 5.4 | 6.3 | 338.875 | 352.087 |
| `ring_write` | 401.662 | 6.4 | 11.7 | 412.178 | 400.953 |
| `histogram_bins` | 517.094 | 7.9 | 14.3 | 551.142 | 531.625 |
| `prefix_scan` | 105.549 | 3.3 | 5.4 | 101.989 | 102.874 |
| `binary_search` | 1001.225 | 14.4 | 36.6 | 887.441 | 1166.315 |
| `sort_window` | 506.209 | 9.2 | 15.3 | 287.108 | 284.670 |
| `bloom_filter` | 296.861 | 9.0 | 27.1 | 315.796 | 292.348 |
| `hash_join` | 952.075 | 17.9 | 42.1 | 965.466 | 956.156 |
| `sieve` | 391.873 | 6.3 | 11.3 | 382.789 | 312.274 |
| `fib` | 576.835 | 10.2 | 31.6 | 509.649 | 488.723 |
| `collatz` | 143.007 | 4.0 | 12.1 | 143.431 | 143.051 |
| `matmul` | 231.189 | 5.7 | 14.7 | 241.231 | 239.702 |
| `json_parse` | 250.807 | 7.4 | 42.2 | 114.789 | 187.039 |
| `nbody` | 623.617 | 13.3 | 25.7 | 611.430 | 650.948 |

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
| _(floor: empty program)_ | _1066_ | _1384_ | _+30 %_ | _8.542_ | _104.578_ | _+1124 %_ |
| `lcg` | 1086 | 1385 | +28 % | 50.846 | 127.167 | +150 % |
| `packet_classifier` | 1085 | 1384 | +28 % | 66.510 | 140.209 | +111 % |
| `ring_write` | 1086 | 1385 | +28 % | 62.579 | 138.349 | +121 % |
| `histogram_bins` | 1086 | 1385 | +28 % | 65.369 | 142.557 | +118 % |
| `prefix_scan` | 1086 | 1385 | +28 % | 31.529 | 104.397 | +231 % |
| `binary_search` | 1086 | 1384 | +28 % | 69.618 | 155.594 | +123 % |
| `sort_window` | 1086 | 1385 | +28 % | 55.134 | 122.120 | +121 % |
| `bloom_filter` | 1086 | 1385 | +28 % | 33.109 | 118.182 | +257 % |
| `hash_join` | 1088 | 1387 | +28 % | 53.282 | 132.029 | +148 % |
| `sieve` | 1086 | 1385 | +28 % | 61.737 | 136.298 | +121 % |
| `fib` | 1085 | 1384 | +28 % | 56.378 | 125.825 | +123 % |
| `collatz` | 1085 | 1384 | +28 % | 35.935 | 107.578 | +199 % |
| `matmul` | 1086 | 1385 | +28 % | 40.374 | 115.019 | +185 % |
| `json_parse` | 1111 | 1407 | +27 % | 33.776 | 107.522 | +218 % |
| `nbody` | 1087 | 1386 | +27 % | 46.747 | 124.487 | +166 % |

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
| _(floor: empty program)_ | _2.080_ | _68.322_ | _37.605_ | _47.770_ | _28.350_ | _48.154_ | _58.433_ |
| `lcg` | 2.340 | 83.920 | 40.136 | 54.322 | 28.771 | 55.092 | 66.275 |
| `packet_classifier` | 2.408 | 82.818 | 37.587 | 53.811 | 29.759 | 52.358 | 63.512 |
| `ring_write` | 2.465 | 82.414 | 40.010 | 51.235 | 29.151 | 54.107 | 74.359 |
| `histogram_bins` | 2.432 | 75.193 | 54.559 | 144.589 | 27.638 | 56.881 | 64.596 |
| `prefix_scan` | 2.517 | 83.066 | 41.123 | 53.438 | 30.350 | 54.376 | 67.219 |
| `binary_search` | 2.569 | 81.783 | 38.053 | 52.015 | 28.439 | 57.612 | 67.052 |
| `sort_window` | 2.670 | 84.114 | 48.140 | 55.982 | 28.639 | 57.671 | 69.543 |
| `bloom_filter` | 2.732 | 78.057 | 58.014 | 60.861 | 27.584 | 57.498 | 65.473 |
| `hash_join` | 4.497 | 159.816 | 92.407 | 83.886 | 27.732 | 83.634 | 95.037 |
| `sieve` | 2.426 | 77.550 | 37.084 | 55.095 | 27.519 | 61.176 | 69.616 |
| `fib` | 2.321 | 75.823 | 37.627 | 49.732 | 41.175 | 51.756 | 61.876 |
| `collatz` | 2.374 | 72.737 | 35.858 | 46.452 | 26.493 | 51.396 | 61.412 |
| `matmul` | 2.811 | 87.885 | 38.613 | 60.721 | 27.850 | 71.976 | 76.968 |
| `json_parse` | 36.213 | 403.374 | 92.698 | 85.613 | 27.698 | 147.005 | 121.431 |
| `nbody` | 3.490 | 92.688 | 43.016 | 68.394 | 27.092 | 71.310 | 82.221 |

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
