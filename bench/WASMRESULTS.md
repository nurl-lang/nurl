# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-09-13T12:30:56Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `54427430972b8aa2ca36fb27d435daaacd09dca7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34757151016 |
| NURL | `v0.64.0-3-g54427430` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.8 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | yes |
| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |
| `nwasm` build | `NURL_SPLIT=0` — `nurl.sh` otherwise lowers a large program as one module per core, and ThinLTO cannot import every callee back across a part boundary. `nwasm` is the subject of section 3, and the reference runtime it is measured against is a release build; a split `nwasm` measured 5.0% slower over this corpus. |

## 1. What wasm costs — native vs the same module on a JIT

Whole-process wall clock in milliseconds, start-up included. The `x`
columns are wasm ÷ native for that language: how much slower the *same
source* got by being compiled to wasm and run under a JIT instead of
straight to the machine. Because all three languages appear, the column
answers a question a NURL-only table could not: whether a gap belongs to
NURL's wasm pipeline or to wasm itself.

| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.282_ | _9.807_ | _7.6_ | _1.226_ | _5.649_ | _4.6_ | _1.318_ | _30.901_ | _23.4_ |
| `lcg` | 37.266 | 61.526 | 1.7 | 37.325 | 62.966 | 1.7 | 37.428 | 72.415 | 1.9 |
| `packet_classifier` | 52.537 | 73.518 | 1.4 | 52.498 | 73.720 | 1.4 | 52.706 | 82.359 | 1.6 |
| `ring_write` | 40.698 | 73.870 | 1.8 | 40.383 | 72.672 | 1.8 | 40.800 | 81.412 | 2.0 |
| `histogram_bins` | 40.596 | 71.990 | 1.8 | 40.387 | 72.364 | 1.8 | 41.047 | 81.054 | 2.0 |
| `prefix_scan` | 21.111 | 37.304 | 1.8 | 21.510 | 35.213 | 1.6 | 20.784 | 43.154 | 2.1 |
| `binary_search` | 29.773 | 87.224 | 2.9 | 29.616 | 88.077 | 3.0 | 32.058 | 102.468 | 3.2 |
| `sort_window` | 37.479 | 68.788 | 1.8 | 45.738 | 56.874 | 1.2 | 35.639 | 66.609 | 1.9 |
| `bloom_filter` | 13.731 | 41.637 | 3.0 | 14.136 | 43.739 | 3.1 | 13.632 | 48.903 | 3.6 |
| `hash_join` | 25.948 | 70.742 | 2.7 | 28.009 | 68.922 | 2.5 | 27.827 | 76.108 | 2.7 |
| `sieve` | 33.835 | 71.376 | 2.1 | 32.798 | 77.304 | 2.4 | 33.598 | 72.484 | 2.2 |
| `fib` | 25.532 | 65.473 | 2.6 | 26.356 | 63.316 | 2.4 | 25.437 | 73.627 | 2.9 |
| `collatz` | 12.642 | 45.951 | 3.6 | 12.590 | 44.878 | 3.6 | 12.541 | 53.484 | 4.3 |
| `matmul` | 17.141 | 47.778 | 2.8 | 16.908 | 41.762 | 2.5 | 17.031 | 51.940 | 3.0 |
| `json_parse` | 9.852 | 53.685 | 5.4 | 7.340 | 36.341 | 5.0 | 9.345 | 54.972 | 5.9 |
| `nbody` | 35.927 | 71.967 | 2.0 | 35.864 | 67.510 | 1.9 | 33.207 | 79.823 | 2.4 |

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
| `lcg` | 1.4 | — | 1.6 | 1.1 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.6 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.6 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.4 | — | 1.5 | — |
| `binary_search` | 2.7 | — | 2.9 | 2.3 |
| `sort_window` | 1.6 | — | 1.2 | 1.0 |
| `bloom_filter` | 2.6 | — | 3.0 | — |
| `hash_join` | 2.5 | — | 2.4 | 1.7 |
| `sieve` | 1.9 | — | 2.3 | 1.3 |
| `fib` | 2.3 | — | 2.3 | 1.8 |
| `collatz` | 3.2 | — | 3.5 | — |
| `matmul` | 2.4 | — | 2.3 | — |
| `json_parse` | 5.1 | — | 5.0 | — |
| `nbody` | 1.8 | — | 1.8 | 1.5 |

## 3. The pure-NURL runtime (`packages/nwasm`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with a template
JIT on top (on by default; `NURL_NWASM_JIT=0` keeps the pure interpreter,
and metered or shared-memory runs fall back to it on their own).
`vs JIT` is the cost of the runtime; `vs native` is the end-to-end
cost of choosing this way to ship. The size of the gap is measured
rather than assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing this runtime *beats* the reference. Nothing surprising
is happening — the reference compiles the whole module before `_start`,
and `nwasm` only decodes it, compiling nothing but what runs. That
crossover is the honest answer to "which runtime should I use": it
depends entirely on how long the guest runs.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C on `nwasm` | Rust on `nwasm` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.495_ | _0.3_ | _1.9_ | _2.100_ | _2.830_ |
| `lcg` | 39.177 | 0.6 | 1.1 | 40.257 | 39.877 |
| `packet_classifier` | 62.166 | 0.8 | 1.2 | 65.531 | 67.653 |
| `ring_write` | 55.438 | 0.8 | 1.4 | 60.918 | 55.364 |
| `histogram_bins` | 59.086 | 0.8 | 1.5 | 60.306 | 64.189 |
| `prefix_scan` | 11.820 | 0.3 | 0.6 | 24.114 | 13.702 |
| `binary_search` | 66.683 | 0.8 | 2.2 | 67.832 | 102.216 |
| `sort_window` | 93.355 | 1.4 | 2.5 | 63.784 | 60.725 |
| `bloom_filter` | 26.440 | 0.6 | 1.9 | 29.254 | 26.816 |
| `hash_join` | 75.108 | 1.1 | 2.9 | 75.050 | 77.571 |
| `sieve` | 52.173 | 0.7 | 1.5 | 55.778 | 54.074 |
| `fib` | 70.441 | 1.1 | 2.8 | 67.451 | 61.006 |
| `collatz` | 29.629 | 0.6 | 2.3 | 32.064 | 31.627 |
| `matmul` | 23.640 | 0.5 | 1.4 | 30.086 | 31.366 |
| `json_parse` | 42.968 | 0.8 | 4.4 | 20.402 | 94.150 |
| `nbody` | 82.853 | 1.2 | 2.3 | 80.306 | 94.103 |

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
| `lcg` | 17 | 1124 | 16 | 915 | 4400 | 2084 |
| `packet_classifier` | 17 | 1124 | 16 | 915 | 4401 | 2083 |
| `ring_write` | 17 | 1124 | 16 | 915 | 4401 | 2084 |
| `histogram_bins` | 17 | 1124 | 16 | 916 | 4401 | 2084 |
| `prefix_scan` | 17 | 1124 | 16 | 916 | 4401 | 2084 |
| `binary_search` | 17 | 1124 | 16 | 916 | 4402 | 2084 |
| `sort_window` | 17 | 1124 | 16 | 917 | 4401 | 2084 |
| `bloom_filter` | 17 | 1124 | 16 | 917 | 4401 | 2084 |
| `hash_join` | 25 | 1126 | 16 | 923 | 4403 | 2086 |
| `sieve` | 17 | 1124 | 16 | 916 | 4400 | 2083 |
| `fib` | 17 | 1124 | 16 | 915 | 4400 | 2083 |
| `collatz` | 17 | 1124 | 16 | 915 | 4400 | 2083 |
| `matmul` | 17 | 1124 | 16 | 917 | 4401 | 2084 |
| `json_parse` | 41 | 1148 | 16 | 1007 | 4414 | 2111 |
| `nbody` | 17 | 1126 | 16 | 919 | 4402 | 2085 |

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
| _(floor: empty program)_ | _1101_ | _1430_ | _+30 %_ | _9.807_ | _142.864_ | _+1357 %_ |
| `lcg` | 1124 | 1430 | +27 % | 61.526 | 174.673 | +184 % |
| `packet_classifier` | 1124 | 1430 | +27 % | 73.518 | 187.741 | +155 % |
| `ring_write` | 1124 | 1430 | +27 % | 73.870 | 188.001 | +155 % |
| `histogram_bins` | 1124 | 1431 | +27 % | 71.990 | 184.836 | +157 % |
| `prefix_scan` | 1124 | 1431 | +27 % | 37.304 | 153.431 | +311 % |
| `binary_search` | 1124 | 1430 | +27 % | 87.224 | 199.877 | +129 % |
| `sort_window` | 1124 | 1431 | +27 % | 68.788 | 177.091 | +157 % |
| `bloom_filter` | 1124 | 1431 | +27 % | 41.637 | 157.360 | +278 % |
| `hash_join` | 1126 | 1433 | +27 % | 70.742 | 176.443 | +149 % |
| `sieve` | 1124 | 1431 | +27 % | 71.376 | 186.977 | +162 % |
| `fib` | 1124 | 1430 | +27 % | 65.473 | 177.114 | +171 % |
| `collatz` | 1124 | 1430 | +27 % | 45.951 | 157.119 | +242 % |
| `matmul` | 1124 | 1431 | +27 % | 47.778 | 158.045 | +231 % |
| `json_parse` | 1148 | 1452 | +27 % | 53.685 | 167.488 | +212 % |
| `nbody` | 1126 | 1432 | +27 % | 71.967 | 182.636 | +154 % |

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
| _(floor: empty program)_ | _2.705_ | _85.725_ | _49.148_ | _49.850_ | _31.576_ | _57.060_ | _67.249_ |
| `lcg` | 2.889 | 99.087 | 49.793 | 56.645 | 32.124 | 64.104 | 74.048 |
| `packet_classifier` | 3.038 | 100.264 | 49.605 | 58.806 | 32.572 | 63.620 | 75.016 |
| `ring_write` | 3.232 | 101.587 | 49.573 | 58.663 | 33.424 | 67.169 | 75.369 |
| `histogram_bins` | 3.339 | 103.343 | 51.393 | 60.827 | 33.700 | 67.874 | 77.474 |
| `prefix_scan` | 3.364 | 105.958 | 50.731 | 63.753 | 32.905 | 67.627 | 78.653 |
| `binary_search` | 3.739 | 105.246 | 52.051 | 59.421 | 32.865 | 70.350 | 79.485 |
| `sort_window` | 3.794 | 111.453 | 52.780 | 66.617 | 32.478 | 74.763 | 84.042 |
| `bloom_filter` | 4.220 | 109.121 | 53.171 | 67.026 | 35.992 | 70.596 | 80.868 |
| `hash_join` | 8.545 | 216.993 | 61.824 | 103.862 | 32.517 | 104.844 | 115.932 |
| `sieve` | 3.427 | 105.021 | 49.926 | 67.489 | 33.424 | 74.432 | 84.905 |
| `fib` | 3.006 | 98.883 | 49.453 | 57.250 | 32.442 | 62.191 | 72.689 |
| `collatz` | 3.241 | 102.669 | 49.778 | 58.153 | 34.154 | 65.988 | 76.519 |
| `matmul` | 3.902 | 109.775 | 52.637 | 70.917 | 33.116 | 88.905 | 94.622 |
| `json_parse` | 101.261 | 606.194 | 188.346 | 107.733 | 34.370 | 175.926 | 152.252 |
| `nbody` | 5.686 | 123.863 | 59.050 | 84.324 | 32.505 | 87.881 | 98.274 |

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
