# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T13:13:55Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `3523ed93edca645d6022f4563d2ea59b618f8810` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32731072065 |
| NURL | `v0.50.0-12-g3523ed93` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.0), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.15.0 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.564_ | _11.542_ | _7.4_ | _1.619_ | _6.867_ | _4.2_ | _1.795_ | _32.523_ | _18.1_ |
| `lcg` | 44.108 | 72.848 | 1.7 | 44.288 | 71.662 | 1.6 | 44.371 | 78.752 | 1.8 |
| `packet_classifier` | 63.457 | 87.330 | 1.4 | 63.520 | 85.899 | 1.4 | 63.729 | 94.293 | 1.5 |
| `ring_write` | 47.627 | 88.006 | 1.8 | 47.669 | 84.973 | 1.8 | 47.898 | 93.240 | 1.9 |
| `histogram_bins` | 44.667 | 85.210 | 1.9 | 44.692 | 83.732 | 1.9 | 44.836 | 89.535 | 2.0 |
| `prefix_scan` | 24.582 | 40.098 | 1.6 | 24.630 | 38.527 | 1.6 | 24.686 | 48.780 | 2.0 |
| `binary_search` | 35.853 | 93.861 | 2.6 | 35.852 | 102.377 | 2.9 | 41.068 | 103.003 | 2.5 |
| `sort_window` | 30.814 | 80.407 | 2.6 | 30.778 | 68.346 | 2.2 | 30.234 | 74.579 | 2.5 |
| `bloom_filter` | 19.715 | 49.218 | 2.5 | 20.385 | 48.123 | 2.4 | 20.749 | 54.305 | 2.6 |
| `hash_join` | 29.154 | 70.086 | 2.4 | 30.744 | 74.540 | 2.4 | 31.190 | 82.065 | 2.6 |
| `sieve` | 20.763 | 59.126 | 2.8 | 20.582 | 66.347 | 3.2 | 20.470 | 63.807 | 3.1 |
| `fib` | 28.021 | 73.913 | 2.6 | 33.361 | 76.132 | 2.3 | 28.188 | 87.177 | 3.1 |
| `collatz` | 13.735 | 49.586 | 3.6 | 13.688 | 48.588 | 3.5 | 13.900 | 57.157 | 4.1 |
| `matmul` | 45.935 | 67.130 | 1.5 | 46.367 | 57.047 | 1.2 | 46.025 | 65.804 | 1.4 |
| `json_parse` | 8.763 | 53.683 | 6.1 | 8.907 | 42.069 | 4.7 | 11.940 | 61.667 | 5.2 |
| `nbody` | 46.137 | 77.735 | 1.7 | 46.281 | 74.293 | 1.6 | 44.114 | 83.592 | 1.9 |

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
| `lcg` | 1.4 | — | 1.5 | 1.1 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.7 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.2 | — | 1.4 | — |
| `binary_search` | 2.4 | — | 2.8 | 1.8 |
| `sort_window` | 2.4 | — | 2.1 | 1.5 |
| `bloom_filter` | 2.1 | — | 2.2 | — |
| `hash_join` | 2.1 | — | 2.3 | 1.7 |
| `sieve` | 2.5 | — | 3.1 | — |
| `fib` | 2.4 | — | 2.2 | 2.1 |
| `collatz` | 3.1 | — | 3.5 | — |
| `matmul` | 1.3 | — | 1.1 | 0.8 |
| `json_parse` | 5.9 | — | 4.8 | — |
| `nbody` | 1.5 | — | 1.5 | 1.2 |

## 3. The pure-NURL runtime (`packages/wasmtime`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with a template
JIT on top (on by default; `NURL_WT_JIT=0` keeps the pure interpreter,
and metered or shared-memory runs fall back to it on their own).
`vs JIT` is the cost of the runtime; `vs native` is the end-to-end
cost of choosing this way to ship. The size of the gap is measured
rather than assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing this runtime *beats* the reference. Nothing surprising
is happening — the reference compiles the whole module before `_start`,
and `wt` only decodes it, compiling nothing but what runs. That
crossover is the honest answer to "which runtime should I use": it
depends entirely on how long the guest runs.

| Benchmark | NURL on `wt` | vs JIT | vs native | C on `wt` | Rust on `wt` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.528_ | _0.2_ | _1.6_ | _2.446_ | _2.829_ |
| `lcg` | 45.843 | 0.6 | 1.0 | 45.779 | 46.320 |
| `packet_classifier` | 75.868 | 0.9 | 1.2 | 75.687 | 76.126 |
| `ring_write` | 63.756 | 0.7 | 1.3 | 65.139 | 63.680 |
| `histogram_bins` | 73.734 | 0.9 | 1.7 | 79.462 | 73.743 |
| `prefix_scan` | 22.758 | 0.6 | 0.9 | 21.106 | 23.222 |
| `binary_search` | 169.738 | 1.8 | 4.7 | 159.027 | 210.452 |
| `sort_window` | 118.137 | 1.5 | 3.8 | 114.603 | 115.224 |
| `bloom_filter` | 50.875 | 1.0 | 2.6 | 55.252 | 50.012 |
| `hash_join` | 104.216 | 1.5 | 3.6 | 116.612 | 114.650 |
| `sieve` | 70.871 | 1.2 | 3.4 | 69.665 | 58.135 |
| `fib` | 125.815 | 1.7 | 4.5 | 121.291 | 108.033 |
| `collatz` | 33.469 | 0.7 | 2.4 | 32.883 | 35.369 |
| `matmul` | 44.344 | 0.7 | 1.0 | 45.062 | 48.971 |
| `json_parse` | 63.591 | 1.2 | 7.3 | 28.710 | 111.245 |
| `nbody` | 294.772 | 3.8 | 6.4 | 689.839 | 755.422 |

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
| `packet_classifier` | 16 | 1092 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1092 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1093 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1093 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1093 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1093 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1093 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1095 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1092 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1092 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1092 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1093 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1118 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1094 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1073_ | _1393_ | _+30 %_ | _11.542_ | _140.326_ | _+1116 %_ |
| `lcg` | 1092 | 1393 | +28 % | 72.848 | 177.303 | +143 % |
| `packet_classifier` | 1092 | 1393 | +28 % | 87.330 | 192.217 | +120 % |
| `ring_write` | 1092 | 1393 | +28 % | 88.006 | 191.610 | +118 % |
| `histogram_bins` | 1093 | 1394 | +28 % | 85.210 | 191.321 | +125 % |
| `prefix_scan` | 1093 | 1394 | +28 % | 40.098 | 148.810 | +271 % |
| `binary_search` | 1093 | 1393 | +28 % | 93.861 | 201.174 | +114 % |
| `sort_window` | 1093 | 1394 | +28 % | 80.407 | 183.214 | +128 % |
| `bloom_filter` | 1093 | 1394 | +28 % | 49.218 | 156.635 | +218 % |
| `hash_join` | 1095 | 1396 | +28 % | 70.086 | 182.964 | +161 % |
| `sieve` | 1092 | 1394 | +28 % | 59.126 | 175.115 | +196 % |
| `fib` | 1092 | 1393 | +28 % | 73.913 | 183.798 | +149 % |
| `collatz` | 1092 | 1393 | +28 % | 49.586 | 156.915 | +216 % |
| `matmul` | 1093 | 1393 | +28 % | 67.130 | 175.077 | +161 % |
| `json_parse` | 1118 | 1416 | +27 % | 53.683 | 162.700 | +203 % |
| `nbody` | 1094 | 1395 | +27 % | 77.735 | 183.197 | +136 % |

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
| _(floor: empty program)_ | _3.159_ | _105.857_ | _65.102_ | _67.591_ | _46.213_ | _60.253_ | _73.377_ |
| `lcg` | 3.148 | 112.802 | 66.772 | 74.601 | 45.784 | 66.105 | 79.477 |
| `packet_classifier` | 3.210 | 113.916 | 65.039 | 73.827 | 46.049 | 64.939 | 79.287 |
| `ring_write` | 3.399 | 116.092 | 65.744 | 76.832 | 46.399 | 67.442 | 81.600 |
| `histogram_bins` | 3.457 | 119.343 | 67.394 | 78.856 | 46.373 | 68.858 | 82.976 |
| `prefix_scan` | 3.456 | 121.094 | 66.903 | 80.777 | 46.181 | 70.029 | 84.314 |
| `binary_search` | 3.656 | 119.105 | 67.238 | 77.437 | 46.920 | 72.468 | 86.394 |
| `sort_window` | 3.713 | 124.820 | 68.349 | 83.088 | 46.874 | 75.908 | 90.389 |
| `bloom_filter` | 3.850 | 123.565 | 70.450 | 86.768 | 46.378 | 72.031 | 85.871 |
| `hash_join` | 6.478 | 231.961 | 76.301 | 124.490 | 46.530 | 107.217 | 121.772 |
| `sieve` | 3.519 | 120.210 | 67.002 | 86.874 | 46.765 | 77.445 | 88.163 |
| `fib` | 3.196 | 113.518 | 65.226 | 75.557 | 46.889 | 65.422 | 78.942 |
| `collatz` | 3.382 | 115.885 | 66.806 | 77.036 | 46.054 | 67.891 | 81.066 |
| `matmul` | 3.724 | 123.791 | 67.567 | 86.448 | 46.117 | 89.014 | 98.118 |
| `json_parse` | 52.240 | 592.125 | 155.600 | 128.401 | 48.065 | 178.706 | 159.161 |
| `nbody` | 5.032 | 133.303 | 75.111 | 101.276 | 46.048 | 91.547 | 103.881 |

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
