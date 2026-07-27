# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-07-27T13:29:47Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `1fb0c3910168f6d01b7ee809e7576e9bb84bd4ed` |
| NURL | `v0.26.0-15-gad7e439` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.82.0 (f6e511eec 2024-10-15) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.1.3), built from this repo |
| C → wasm | `zig 0.13.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 44.0.0 (af382d7d9 2026-04-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.6.2 (pure NURL)) — interpreter, built from this repo |

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
| _(floor: empty program)_ | _1.630_ | _9.808_ | _6.0_ | _1.438_ | _7.619_ | _5.3_ | _1.840_ | _18.035_ | _9.8_ |
| `lcg` | 41.624 | 64.622 | 1.6 | 41.394 | 59.554 | 1.4 | 41.065 | 55.123 | 1.3 |
| `affine_mix` | 40.491 | 63.282 | 1.6 | 40.201 | 62.742 | 1.6 | 40.566 | 53.242 | 1.3 |
| `packet_classifier` | 69.816 | 78.881 | 1.1 | 68.346 | 73.882 | 1.1 | 69.318 | 70.075 | 1.0 |
| `ring_write` | 34.609 | 72.112 | 2.1 | 43.404 | 68.473 | 1.6 | 43.489 | 64.680 | 1.5 |
| `histogram_bins` | 40.470 | 72.774 | 1.8 | 41.662 | 77.391 | 1.9 | 42.208 | 65.527 | 1.6 |
| `prefix_scan` | 24.483 | 50.935 | 2.1 | 24.519 | 49.366 | 2.0 | 24.694 | 30.135 | 1.2 |
| `binary_search` | 27.827 | 106.105 | 3.8 | 36.842 | 122.968 | 3.3 | 38.621 | 97.924 | 2.5 |
| `sort_window` | 47.993 | 88.674 | 1.8 | 52.282 | 69.588 | 1.3 | 53.636 | 124.895 | 2.3 |
| `bloom_filter` | 18.282 | 45.686 | 2.5 | 16.320 | 45.641 | 2.8 | 18.319 | 36.393 | 2.0 |
| `hash_join` | 5.827 | 31.931 | 5.5 | 6.360 | 31.983 | 5.0 | 6.930 | 24.949 | 3.6 |
| `sieve` | 43.101 | 69.058 | 1.6 | 42.599 | 68.776 | 1.6 | 38.246 | 62.095 | 1.6 |
| `fib` | 33.530 | 71.419 | 2.1 | 27.659 | 67.501 | 2.4 | 34.853 | 63.020 | 1.8 |
| `collatz` | 15.506 | 42.037 | 2.7 | 13.688 | 41.872 | 3.1 | 18.640 | 37.746 | 2.0 |
| `matmul` | 34.727 | 62.747 | 1.8 | 34.885 | 59.194 | 1.7 | 35.248 | 53.746 | 1.5 |
| `json_parse` | 12.388 | 51.705 | 4.2 | 12.162 | 35.537 | 2.9 | 14.812 | 40.459 | 2.7 |

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
| `lcg` | 1.4 | — | 1.3 | 0.9 |
| `affine_mix` | 1.4 | — | 1.4 | 0.9 |
| `packet_classifier` | 1.0 | — | 1.0 | 0.8 |
| `ring_write` | 1.9 | — | 1.5 | 1.1 |
| `histogram_bins` | 1.6 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.8 | — | 1.8 | — |
| `binary_search` | 3.7 | 3.0 | 3.3 | 2.2 |
| `sort_window` | 1.7 | — | 1.2 | 2.1 |
| `bloom_filter` | 2.2 | — | 2.6 | 1.1 |
| `hash_join` | 5.3 | — | 5.0 | — |
| `sieve` | 1.4 | — | 1.5 | 1.2 |
| `fib` | 1.9 | — | 2.3 | 1.4 |
| `collatz` | 2.3 | — | 2.8 | 1.2 |
| `matmul` | 1.6 | — | 1.5 | 1.1 |
| `json_parse` | 3.9 | — | 2.6 | 1.7 |

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
| _(floor: empty program)_ | _44.731_ | _4.6_ | _27.4_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 1625.179 | 25.1 | 39.0 | SKIPPED | SKIPPED |
| `affine_mix` | 3507.907 | 55.4 | 86.6 | SKIPPED | SKIPPED |
| `packet_classifier` | 3877.192 | 49.2 | 55.5 | SKIPPED | SKIPPED |
| `ring_write` | 4913.754 | 68.1 | 142.0 | SKIPPED | SKIPPED |
| `histogram_bins` | 5455.946 | 75.0 | 134.8 | SKIPPED | SKIPPED |
| `prefix_scan` | 1616.300 | 31.7 | 66.0 | SKIPPED | SKIPPED |
| `binary_search` | 9388.097 | 88.5 | 337.4 | SKIPPED | SKIPPED |
| `sort_window` | 13275.200 | 149.7 | 276.6 | SKIPPED | SKIPPED |
| `bloom_filter` | 3039.191 | 66.5 | 166.2 | SKIPPED | SKIPPED |
| `hash_join` | 1027.614 | 32.2 | 176.4 | SKIPPED | SKIPPED |
| `sieve` | 3724.374 | 53.9 | 86.4 | SKIPPED | SKIPPED |
| `fib` | 5489.885 | 76.9 | 163.7 | SKIPPED | SKIPPED |
| `collatz` | 2057.613 | 48.9 | 132.7 | SKIPPED | SKIPPED |
| `matmul` | 3464.876 | 55.2 | 99.8 | SKIPPED | SKIPPED |
| `json_parse` | 3955.597 | 76.5 | 319.3 | SKIPPED | SKIPPED |

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
| _(floor: empty program)_ | _798_ | _1063_ | _+33 %_ | _9.808_ | _59.708_ | _+509 %_ |
| `lcg` | 819 | 1064 | +30 % | 64.622 | 92.085 | +42 % |
| `affine_mix` | 819 | 1064 | +30 % | 63.282 | 95.137 | +50 % |
| `packet_classifier` | 819 | 1064 | +30 % | 78.881 | 110.148 | +40 % |
| `ring_write` | 819 | 1064 | +30 % | 72.112 | 99.371 | +38 % |
| `histogram_bins` | 819 | 1064 | +30 % | 72.774 | 99.882 | +37 % |
| `prefix_scan` | 820 | 1064 | +30 % | 50.935 | 79.919 | +57 % |
| `binary_search` | 819 | 1064 | +30 % | 106.105 | 138.638 | +31 % |
| `sort_window` | 820 | 1064 | +30 % | 88.674 | 115.168 | +30 % |
| `bloom_filter` | 820 | 1064 | +30 % | 45.686 | 75.025 | +64 % |
| `hash_join` | 821 | 1067 | +30 % | 31.931 | 60.431 | +89 % |
| `sieve` | 819 | 1064 | +30 % | 69.058 | 97.185 | +41 % |
| `fib` | 819 | 1064 | +30 % | 71.419 | 101.919 | +43 % |
| `collatz` | 819 | 1064 | +30 % | 42.037 | 78.965 | +88 % |
| `matmul` | 820 | 1064 | +30 % | 62.747 | 95.525 | +52 % |
| `json_parse` | 849 | 1119 | +32 % | 51.705 | 86.664 | +68 % |

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
| _(floor: empty program)_ | _3.109_ | _94.259_ | _1321.658_ | _76.993_ | _582.738_ | _159.963_ | _98.807_ |
| `lcg` | 3.943 | 111.768 | 1317.186 | 83.074 | 923.822 | 172.949 | 122.350 |
| `affine_mix` | 4.087 | 111.887 | 1309.301 | 89.481 | 945.634 | 175.488 | 114.755 |
| `packet_classifier` | 4.037 | 112.595 | 1317.558 | 90.056 | 921.645 | 171.641 | 117.374 |
| `ring_write` | 3.945 | 111.381 | 1294.669 | 87.314 | 913.401 | 173.073 | 124.634 |
| `histogram_bins` | 3.992 | 115.684 | 1290.093 | 85.553 | 914.425 | 166.910 | 121.552 |
| `prefix_scan` | 4.187 | 114.961 | 1293.621 | 92.298 | 930.271 | 178.589 | 116.180 |
| `binary_search` | 5.111 | 114.878 | 1295.557 | 88.012 | 907.271 | 176.809 | 113.993 |
| `sort_window` | 3.891 | 118.102 | 1289.033 | 98.143 | 917.096 | 188.156 | 124.645 |
| `bloom_filter` | 5.317 | 118.238 | 1299.433 | 98.562 | 915.727 | 181.701 | 122.398 |
| `hash_join` | 8.837 | 246.071 | 1312.725 | 145.608 | 965.219 | 231.746 | 176.391 |
| `sieve` | 4.499 | 109.583 | 1296.217 | 100.093 | 911.611 | 187.737 | 127.761 |
| `fib` | 3.977 | 111.396 | 1301.375 | 86.302 | 913.675 | 167.798 | 112.004 |
| `collatz` | 4.726 | 112.897 | 1290.592 | 88.679 | 911.740 | 171.371 | 112.529 |
| `matmul` | 5.543 | 125.582 | 1287.905 | 101.021 | 925.790 | 208.094 | 150.988 |
| `json_parse` | 81.852 | 835.901 | 1517.117 | 138.034 | 1068.154 | 317.353 | 232.082 |

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
