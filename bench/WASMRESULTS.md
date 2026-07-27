# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-07-27T14:04:06Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Host | `Linux x86_64` |
| Kernel | `Linux 7.0.0-28-generic x86_64` |
| CPU | Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz (12 logical cores) |
| Memory | 32770952 KiB |
| Commit | `3df12c8fff23aaff224379d87f0ee345fdb65ffe` |
| NURL | `v0.26.0-15-gad7e439` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.82.0 (f6e511eec 2024-10-15) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.3), built from this repo |
| C → wasm | `zig 0.13.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 44.0.0 (af382d7d9 2026-04-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.7.0 (pure NURL)) — interpreter, built from this repo |

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
| _(floor: empty program)_ | _1.688_ | _9.879_ | _5.9_ | _1.587_ | _7.419_ | _4.7_ | _2.027_ | _17.995_ | _8.9_ |
| `lcg` | 40.321 | 68.052 | 1.7 | 40.612 | 57.430 | 1.4 | 40.757 | 55.982 | 1.4 |
| `affine_mix` | 34.774 | 62.917 | 1.8 | 35.451 | 64.321 | 1.8 | 40.729 | 55.224 | 1.4 |
| `packet_classifier` | 69.669 | 77.184 | 1.1 | 68.344 | 78.582 | 1.1 | 68.728 | 70.103 | 1.0 |
| `ring_write` | 43.609 | 76.451 | 1.8 | 43.372 | 77.892 | 1.8 | 44.789 | 63.468 | 1.4 |
| `histogram_bins` | 36.637 | 69.946 | 1.9 | 42.629 | 73.772 | 1.7 | 42.006 | 66.824 | 1.6 |
| `prefix_scan` | 25.098 | 51.475 | 2.1 | 24.749 | 54.309 | 2.2 | 25.063 | 30.717 | 1.2 |
| `binary_search` | 30.206 | 109.314 | 3.6 | 37.304 | 117.660 | 3.2 | 44.395 | 97.726 | 2.2 |
| `sort_window` | 40.579 | 87.176 | 2.1 | 52.434 | 71.826 | 1.4 | 53.602 | 122.927 | 2.3 |
| `bloom_filter` | 18.781 | 47.761 | 2.5 | 16.279 | 44.378 | 2.7 | 17.080 | 35.243 | 2.1 |
| `hash_join` | 6.442 | 31.290 | 4.9 | 6.521 | 33.240 | 5.1 | 6.992 | 26.679 | 3.8 |
| `sieve` | 42.853 | 67.343 | 1.6 | 42.419 | 62.898 | 1.5 | 42.144 | 61.232 | 1.5 |
| `fib` | 34.479 | 70.364 | 2.0 | 33.697 | 66.033 | 2.0 | 33.425 | 63.855 | 1.9 |
| `collatz` | 18.864 | 44.047 | 2.3 | 13.390 | 43.014 | 3.2 | 13.377 | 38.933 | 2.9 |
| `matmul` | 34.544 | 62.749 | 1.8 | 34.942 | 65.766 | 1.9 | 34.734 | 56.088 | 1.6 |
| `json_parse` | 13.058 | 51.805 | 4.0 | 12.261 | 41.163 | 3.4 | 14.987 | 38.574 | 2.6 |

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
| `lcg` | 1.5 | — | 1.3 | 1.0 |
| `affine_mix` | 1.6 | — | 1.7 | 1.0 |
| `packet_classifier` | 1.0 | — | 1.1 | 0.8 |
| `ring_write` | 1.6 | — | 1.7 | 1.1 |
| `histogram_bins` | 1.7 | — | 1.6 | 1.2 |
| `prefix_scan` | 1.8 | — | 2.0 | — |
| `binary_search` | 3.5 | 2.6 | 3.1 | 1.9 |
| `sort_window` | 2.0 | 1.6 | 1.3 | 2.0 |
| `bloom_filter` | 2.2 | — | 2.5 | — |
| `hash_join` | 4.5 | — | 5.2 | — |
| `sieve` | 1.4 | — | 1.4 | 1.1 |
| `fib` | 1.8 | — | 1.8 | 1.5 |
| `collatz` | 2.0 | — | 3.0 | 1.8 |
| `matmul` | 1.6 | — | 1.7 | 1.2 |
| `json_parse` | 3.7 | — | 3.2 | 1.6 |

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
| _(floor: empty program)_ | _49.545_ | _5.0_ | _29.4_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 944.366 | 13.9 | 23.4 | SKIPPED | SKIPPED |
| `affine_mix` | 1756.028 | 27.9 | 50.5 | SKIPPED | SKIPPED |
| `packet_classifier` | 2297.956 | 29.8 | 33.0 | SKIPPED | SKIPPED |
| `ring_write` | 2538.857 | 33.2 | 58.2 | SKIPPED | SKIPPED |
| `histogram_bins` | 3120.925 | 44.6 | 85.2 | SKIPPED | SKIPPED |
| `prefix_scan` | 804.122 | 15.6 | 32.0 | SKIPPED | SKIPPED |
| `binary_search` | 5203.906 | 47.6 | 172.3 | SKIPPED | SKIPPED |
| `sort_window` | 5450.679 | 62.5 | 134.3 | SKIPPED | SKIPPED |
| `bloom_filter` | 1645.435 | 34.5 | 87.6 | SKIPPED | SKIPPED |
| `hash_join` | 533.682 | 17.1 | 82.8 | SKIPPED | SKIPPED |
| `sieve` | 1969.232 | 29.2 | 46.0 | SKIPPED | SKIPPED |
| `fib` | 4525.922 | 64.3 | 131.3 | SKIPPED | SKIPPED |
| `collatz` | 977.852 | 22.2 | 51.8 | SKIPPED | SKIPPED |
| `matmul` | 1548.370 | 24.7 | 44.8 | SKIPPED | SKIPPED |
| `json_parse` | 1886.211 | 36.4 | 144.4 | SKIPPED | SKIPPED |

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
| `lcg` | 16 | 819 | 16 | 686 | 3743 | 1733 |
| `affine_mix` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `packet_classifier` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `ring_write` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `histogram_bins` | 16 | 819 | 16 | 686 | 3743 | 1734 |
| `prefix_scan` | 16 | 820 | 16 | 687 | 3743 | 1734 |
| `binary_search` | 16 | 819 | 16 | 687 | 3743 | 1735 |
| `sort_window` | 16 | 820 | 16 | 687 | 3743 | 1734 |
| `bloom_filter` | 16 | 820 | 16 | 687 | 3743 | 1734 |
| `hash_join` | 20 | 821 | 16 | 695 | 3743 | 1736 |
| `sieve` | 16 | 819 | 16 | 691 | 3742 | 1733 |
| `fib` | 16 | 819 | 16 | 686 | 3738 | 1733 |
| `collatz` | 16 | 819 | 16 | 686 | 3738 | 1733 |
| `matmul` | 16 | 820 | 16 | 691 | 3743 | 1734 |
| `json_parse` | 34 | 849 | 16 | 736 | 3757 | 1763 |

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
| _(floor: empty program)_ | _798_ | _1063_ | _+33 %_ | _9.879_ | _56.825_ | _+475 %_ |
| `lcg` | 819 | 1064 | +30 % | 68.052 | 92.761 | +36 % |
| `affine_mix` | 819 | 1064 | +30 % | 62.917 | 92.808 | +48 % |
| `packet_classifier` | 819 | 1064 | +30 % | 77.184 | 105.714 | +37 % |
| `ring_write` | 819 | 1064 | +30 % | 76.451 | 105.333 | +38 % |
| `histogram_bins` | 819 | 1064 | +30 % | 69.946 | 100.797 | +44 % |
| `prefix_scan` | 820 | 1064 | +30 % | 51.475 | 80.473 | +56 % |
| `binary_search` | 819 | 1064 | +30 % | 109.314 | 130.598 | +19 % |
| `sort_window` | 820 | 1064 | +30 % | 87.176 | 119.717 | +37 % |
| `bloom_filter` | 820 | 1064 | +30 % | 47.761 | 75.717 | +59 % |
| `hash_join` | 821 | 1067 | +30 % | 31.290 | 65.062 | +108 % |
| `sieve` | 819 | 1064 | +30 % | 67.343 | 94.972 | +41 % |
| `fib` | 819 | 1064 | +30 % | 70.364 | 95.511 | +36 % |
| `collatz` | 819 | 1064 | +30 % | 44.047 | 83.803 | +90 % |
| `matmul` | 820 | 1064 | +30 % | 62.749 | 88.426 | +41 % |
| `json_parse` | 849 | 1119 | +32 % | 51.805 | 86.904 | +68 % |

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
| _(floor: empty program)_ | _2.792_ | _91.027_ | _1310.349_ | _76.817_ | _577.141_ | _153.022_ | _105.605_ |
| `lcg` | 3.800 | 110.973 | 1306.881 | 85.149 | 927.763 | 174.120 | 113.821 |
| `affine_mix` | 3.513 | 112.565 | 1307.338 | 91.722 | 927.368 | 172.119 | 118.537 |
| `packet_classifier` | 3.960 | 112.538 | 1299.299 | 85.318 | 920.908 | 175.551 | 112.071 |
| `ring_write` | 4.130 | 112.268 | 1293.855 | 90.058 | 936.186 | 166.781 | 115.605 |
| `histogram_bins` | 5.251 | 112.498 | 1284.269 | 90.890 | 916.651 | 168.279 | 112.495 |
| `prefix_scan` | 4.240 | 118.993 | 1293.428 | 93.376 | 922.745 | 174.073 | 122.173 |
| `binary_search` | 4.987 | 117.264 | 1284.894 | 87.611 | 912.935 | 175.793 | 115.941 |
| `sort_window` | 4.662 | 120.994 | 1288.314 | 98.953 | 918.989 | 185.489 | 127.930 |
| `bloom_filter` | 5.049 | 120.654 | 1288.255 | 98.838 | 921.665 | 173.867 | 116.930 |
| `hash_join` | 10.926 | 241.104 | 1295.604 | 136.518 | 955.157 | 224.718 | 170.004 |
| `sieve` | 4.597 | 117.581 | 1294.942 | 98.679 | 950.892 | 188.504 | 134.800 |
| `fib` | 3.777 | 111.690 | 1290.282 | 82.342 | 906.320 | 169.206 | 110.839 |
| `collatz` | 4.189 | 112.972 | 1289.783 | 87.520 | 919.680 | 172.534 | 122.063 |
| `matmul` | 5.184 | 122.055 | 1303.377 | 100.389 | 922.193 | 212.437 | 145.561 |
| `json_parse` | 83.262 | 842.075 | 1496.062 | 143.229 | 1064.956 | 318.020 | 226.224 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `affine_mix` | `227901546981696845` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `2814341850483607168` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |

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
