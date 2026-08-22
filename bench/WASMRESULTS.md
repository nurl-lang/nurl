# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-22T08:54:13Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `96732834433c1660b09f20695552fd825eda8891` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32563296158 |
| NURL | `v0.48.0-6-g96732834` |
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
| _(floor: empty program)_ | _1.141_ | _10.160_ | _8.9_ | _1.153_ | _5.971_ | _5.2_ | _1.297_ | _28.443_ | _21.9_ |
| `lcg` | 30.886 | 50.705 | 1.6 | 30.797 | 49.943 | 1.6 | 31.027 | 53.887 | 1.7 |
| `packet_classifier` | 48.920 | 58.674 | 1.2 | 52.107 | 58.114 | 1.1 | 52.396 | 65.762 | 1.3 |
| `ring_write` | 33.753 | 61.102 | 1.8 | 33.924 | 59.623 | 1.8 | 33.551 | 65.221 | 1.9 |
| `histogram_bins` | 34.390 | 60.323 | 1.8 | 32.112 | 60.158 | 1.9 | 31.835 | 64.730 | 2.0 |
| `prefix_scan` | 17.117 | 30.138 | 1.8 | 17.385 | 29.426 | 1.7 | 18.789 | 34.732 | 1.8 |
| `binary_search` | 26.059 | 65.332 | 2.5 | 22.959 | 61.557 | 2.7 | 25.289 | 71.729 | 2.8 |
| `sort_window` | 32.120 | 51.008 | 1.6 | 38.944 | 48.826 | 1.3 | 30.873 | 52.186 | 1.7 |
| `bloom_filter` | 10.760 | 31.097 | 2.9 | 10.772 | 29.446 | 2.7 | 10.863 | 34.212 | 3.1 |
| `hash_join` | 18.324 | 49.255 | 2.7 | 19.740 | 53.097 | 2.7 | 19.853 | 56.833 | 2.9 |
| `sieve` | 33.100 | 59.224 | 1.8 | 32.579 | 59.992 | 1.8 | 34.173 | 65.077 | 1.9 |
| `fib` | 17.372 | 51.847 | 3.0 | 20.387 | 44.374 | 2.2 | 17.537 | 55.671 | 3.2 |
| `collatz` | 11.305 | 34.058 | 3.0 | 11.506 | 32.412 | 2.8 | 12.140 | 38.246 | 3.2 |
| `matmul` | 14.407 | 35.003 | 2.4 | 15.017 | 32.105 | 2.1 | 15.277 | 38.525 | 2.5 |
| `json_parse` | 5.730 | 34.546 | 6.0 | 5.977 | 26.945 | 4.5 | 7.139 | 39.412 | 5.5 |
| `nbody` | 23.698 | 48.976 | 2.1 | 23.717 | 42.463 | 1.8 | 21.777 | 51.381 | 2.4 |

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
| `ring_write` | 1.6 | — | 1.6 | 1.1 |
| `histogram_bins` | 1.5 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.3 | — | 1.4 | — |
| `binary_search` | 2.2 | — | 2.5 | 1.8 |
| `sort_window` | 1.3 | — | 1.1 | — |
| `bloom_filter` | 2.2 | — | 2.4 | — |
| `hash_join` | 2.3 | — | 2.5 | — |
| `sieve` | 1.5 | — | 1.7 | 1.1 |
| `fib` | 2.6 | — | 2.0 | — |
| `collatz` | 2.4 | — | 2.6 | — |
| `matmul` | 1.9 | — | 1.9 | — |
| `json_parse` | 5.3 | — | 4.3 | — |
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
| _(floor: empty program)_ | _1.622_ | _0.2_ | _1.4_ | _1.515_ | _1.850_ |
| `lcg` | 154.321 | 3.0 | 5.0 | 159.900 | 158.789 |
| `packet_classifier` | 314.049 | 5.4 | 6.4 | 318.401 | 327.719 |
| `ring_write` | 426.347 | 7.0 | 12.6 | 441.680 | 385.267 |
| `histogram_bins` | 499.922 | 8.3 | 14.5 | 530.798 | 505.631 |
| `prefix_scan` | 101.642 | 3.4 | 5.9 | 92.741 | 102.048 |
| `binary_search` | 942.882 | 14.4 | 36.2 | 855.090 | 1127.190 |
| `sort_window` | 498.369 | 9.8 | 15.5 | 274.735 | 275.714 |
| `bloom_filter` | 281.656 | 9.1 | 26.2 | 311.213 | 280.416 |
| `hash_join` | 901.630 | 18.3 | 49.2 | 923.283 | 924.366 |
| `sieve` | 356.218 | 6.0 | 10.8 | 365.264 | 299.059 |
| `fib` | 503.300 | 9.7 | 29.0 | 535.657 | 528.091 |
| `collatz` | 140.139 | 4.1 | 12.4 | 138.758 | 139.070 |
| `matmul` | 225.759 | 6.4 | 15.7 | 235.284 | 233.011 |
| `json_parse` | 239.109 | 6.9 | 41.7 | 109.092 | 180.217 |
| `nbody` | 607.790 | 12.4 | 25.6 | 596.294 | 622.387 |

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
| _(floor: empty program)_ | _1066_ | _1384_ | _+30 %_ | _10.160_ | _100.045_ | _+885 %_ |
| `lcg` | 1086 | 1385 | +28 % | 50.705 | 121.321 | +139 % |
| `packet_classifier` | 1085 | 1384 | +28 % | 58.674 | 129.827 | +121 % |
| `ring_write` | 1086 | 1385 | +28 % | 61.102 | 133.261 | +118 % |
| `histogram_bins` | 1086 | 1385 | +28 % | 60.323 | 129.156 | +114 % |
| `prefix_scan` | 1086 | 1385 | +28 % | 30.138 | 104.850 | +248 % |
| `binary_search` | 1086 | 1384 | +28 % | 65.332 | 137.728 | +111 % |
| `sort_window` | 1086 | 1385 | +28 % | 51.008 | 124.051 | +143 % |
| `bloom_filter` | 1086 | 1385 | +28 % | 31.097 | 103.086 | +231 % |
| `hash_join` | 1088 | 1387 | +28 % | 49.255 | 118.390 | +140 % |
| `sieve` | 1086 | 1385 | +28 % | 59.224 | 131.077 | +121 % |
| `fib` | 1085 | 1384 | +28 % | 51.847 | 120.852 | +133 % |
| `collatz` | 1085 | 1384 | +28 % | 34.058 | 107.219 | +215 % |
| `matmul` | 1086 | 1385 | +28 % | 35.003 | 104.322 | +198 % |
| `json_parse` | 1111 | 1407 | +27 % | 34.546 | 105.151 | +204 % |
| `nbody` | 1087 | 1386 | +27 % | 48.976 | 118.804 | +143 % |

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
| _(floor: empty program)_ | _5.135_ | _76.001_ | _161.226_ | _44.211_ | _25.275_ | _51.644_ | _62.127_ |
| `lcg` | 2.071 | 70.128 | 36.066 | 46.261 | 26.921 | 50.345 | 60.685 |
| `packet_classifier` | 2.284 | 74.031 | 36.498 | 50.048 | 26.832 | 50.807 | 61.589 |
| `ring_write` | 2.448 | 80.201 | 37.243 | 52.358 | 27.960 | 53.418 | 63.808 |
| `histogram_bins` | 2.353 | 75.705 | 37.845 | 50.181 | 45.115 | 53.681 | 70.183 |
| `prefix_scan` | 2.431 | 81.732 | 39.910 | 55.512 | 30.278 | 55.485 | 67.252 |
| `binary_search` | 2.551 | 80.981 | 53.797 | 52.731 | 43.152 | 56.733 | 67.266 |
| `sort_window` | 2.781 | 91.143 | 43.859 | 60.034 | 29.651 | 64.487 | 70.329 |
| `bloom_filter` | 2.752 | 81.942 | 37.503 | 54.237 | 25.912 | 57.302 | 64.363 |
| `hash_join` | 4.765 | 158.166 | 42.046 | 114.382 | 77.163 | 82.176 | 93.495 |
| `sieve` | 2.427 | 77.729 | 49.810 | 54.360 | 41.443 | 59.955 | 71.053 |
| `fib` | 2.235 | 70.204 | 36.187 | 45.068 | 26.629 | 48.636 | 58.828 |
| `collatz` | 2.408 | 70.914 | 35.658 | 46.454 | 41.257 | 50.707 | 59.880 |
| `matmul` | 2.488 | 74.129 | 37.175 | 52.267 | 31.364 | 67.566 | 79.054 |
| `json_parse` | 35.251 | 392.400 | 155.324 | 84.903 | 32.664 | 137.255 | 120.155 |
| `nbody` | 3.350 | 89.037 | 46.102 | 67.686 | 58.685 | 75.279 | 84.095 |

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
