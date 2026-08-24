# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T17:09:18Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `fedfb4c4a199e2efdb9aed1ae65760ac9543d0da` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32754701519 |
| NURL | `v0.50.0-21-gfedfb4c4` |
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
| _(floor: empty program)_ | _1.230_ | _10.401_ | _8.5_ | _1.268_ | _6.214_ | _4.9_ | _1.444_ | _29.310_ | _20.3_ |
| `lcg` | 35.536 | 60.391 | 1.7 | 35.417 | 58.341 | 1.6 | 35.309 | 62.756 | 1.8 |
| `packet_classifier` | 49.246 | 68.598 | 1.4 | 49.295 | 67.570 | 1.4 | 49.405 | 73.334 | 1.5 |
| `ring_write` | 36.950 | 67.570 | 1.8 | 36.998 | 68.389 | 1.8 | 37.038 | 79.474 | 2.1 |
| `histogram_bins` | 35.703 | 68.016 | 1.9 | 36.182 | 65.028 | 1.8 | 35.991 | 72.378 | 2.0 |
| `prefix_scan` | 18.982 | 34.889 | 1.8 | 18.985 | 30.687 | 1.6 | 19.094 | 36.324 | 1.9 |
| `binary_search` | 27.672 | 73.494 | 2.7 | 27.813 | 77.800 | 2.8 | 31.737 | 80.190 | 2.5 |
| `sort_window` | 23.811 | 58.443 | 2.5 | 23.812 | 51.622 | 2.2 | 23.409 | 55.318 | 2.4 |
| `bloom_filter` | 16.370 | 40.051 | 2.4 | 16.705 | 40.845 | 2.4 | 16.944 | 47.722 | 2.8 |
| `hash_join` | 22.551 | 64.619 | 2.9 | 23.770 | 58.904 | 2.5 | 24.042 | 72.024 | 3.0 |
| `sieve` | 15.779 | 51.181 | 3.2 | 15.612 | 49.507 | 3.2 | 15.711 | 47.568 | 3.0 |
| `fib` | 21.624 | 56.726 | 2.6 | 25.807 | 55.793 | 2.2 | 21.788 | 69.759 | 3.2 |
| `collatz` | 10.784 | 41.802 | 3.9 | 12.724 | 39.291 | 3.1 | 10.833 | 46.759 | 4.3 |
| `matmul` | 35.170 | 52.667 | 1.5 | 35.819 | 44.219 | 1.2 | 36.456 | 51.268 | 1.4 |
| `json_parse` | 6.724 | 45.731 | 6.8 | 7.098 | 38.086 | 5.4 | 9.238 | 46.345 | 5.0 |
| `nbody` | 36.643 | 61.010 | 1.7 | 35.771 | 58.424 | 1.6 | 34.112 | 63.718 | 1.9 |

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
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.6 | — | 1.7 | 1.4 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.4 | — |
| `binary_search` | 2.4 | — | 2.7 | 1.7 |
| `sort_window` | 2.1 | — | 2.0 | — |
| `bloom_filter` | 2.0 | — | 2.2 | — |
| `hash_join` | 2.5 | — | 2.3 | 1.9 |
| `sieve` | 2.8 | — | 3.0 | — |
| `fib` | 2.3 | — | 2.0 | 2.0 |
| `collatz` | 3.3 | — | 2.9 | — |
| `matmul` | 1.2 | — | 1.1 | — |
| `json_parse` | 6.4 | — | 5.5 | — |
| `nbody` | 1.4 | — | 1.5 | 1.1 |

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
| _(floor: empty program)_ | _2.854_ | _0.3_ | _2.3_ | _2.696_ | _2.523_ |
| `lcg` | 35.844 | 0.6 | 1.0 | 36.132 | 36.424 |
| `packet_classifier` | 56.913 | 0.8 | 1.2 | 59.499 | 65.717 |
| `ring_write` | 51.855 | 0.8 | 1.4 | 48.939 | 48.845 |
| `histogram_bins` | 46.428 | 0.7 | 1.3 | 49.408 | 53.164 |
| `prefix_scan` | 13.738 | 0.4 | 0.7 | 13.276 | 14.178 |
| `binary_search` | 108.255 | 1.5 | 3.9 | 97.418 | 134.772 |
| `sort_window` | 71.877 | 1.2 | 3.0 | 87.114 | 85.744 |
| `bloom_filter` | 32.782 | 0.8 | 2.0 | 29.820 | 33.914 |
| `hash_join` | 64.672 | 1.0 | 2.9 | 66.692 | 63.985 |
| `sieve` | 38.404 | 0.8 | 2.4 | 39.558 | 33.817 |
| `fib` | 102.765 | 1.8 | 4.8 | 98.469 | 85.223 |
| `collatz` | 24.429 | 0.6 | 2.3 | 24.433 | 24.977 |
| `matmul` | 25.634 | 0.5 | 0.7 | 28.725 | 29.154 |
| `json_parse` | 47.239 | 1.0 | 7.0 | 25.629 | 93.502 |
| `nbody` | 104.534 | 1.7 | 2.9 | 570.148 | 626.843 |

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
| `lcg` | 16 | 1093 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 16 | 1093 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1093 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1093 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1094 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1093 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1094 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1093 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1095 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1093 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1093 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1119 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1095 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _10.401_ | _117.961_ | _+1034 %_ |
| `lcg` | 1093 | 1394 | +28 % | 60.391 | 140.679 | +133 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 68.598 | 149.931 | +119 % |
| `ring_write` | 1093 | 1394 | +28 % | 67.570 | 153.548 | +127 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 68.016 | 148.285 | +118 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 34.889 | 114.073 | +227 % |
| `binary_search` | 1093 | 1394 | +28 % | 73.494 | 161.741 | +120 % |
| `sort_window` | 1094 | 1395 | +28 % | 58.443 | 140.271 | +140 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 40.051 | 122.773 | +207 % |
| `hash_join` | 1095 | 1397 | +28 % | 64.619 | 145.544 | +125 % |
| `sieve` | 1093 | 1394 | +28 % | 51.181 | 139.013 | +172 % |
| `fib` | 1093 | 1394 | +28 % | 56.726 | 149.138 | +163 % |
| `collatz` | 1093 | 1394 | +28 % | 41.802 | 127.175 | +204 % |
| `matmul` | 1093 | 1394 | +28 % | 52.667 | 132.034 | +151 % |
| `json_parse` | 1119 | 1417 | +27 % | 45.731 | 133.159 | +191 % |
| `nbody` | 1095 | 1396 | +27 % | 61.010 | 142.887 | +134 % |

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
| _(floor: empty program)_ | _2.340_ | _81.113_ | _50.653_ | _52.653_ | _45.483_ | _57.862_ | _64.624_ |
| `lcg` | 2.686 | 105.181 | 53.363 | 67.363 | 35.777 | 54.898 | 65.333 |
| `packet_classifier` | 2.533 | 89.536 | 53.443 | 60.768 | 36.310 | 52.764 | 62.913 |
| `ring_write` | 2.821 | 98.183 | 53.791 | 62.788 | 37.720 | 55.866 | 64.160 |
| `histogram_bins` | 2.866 | 99.258 | 53.962 | 66.948 | 37.580 | 60.475 | 68.310 |
| `prefix_scan` | 2.729 | 93.570 | 51.903 | 64.018 | 35.461 | 55.157 | 66.332 |
| `binary_search` | 2.864 | 94.759 | 63.635 | 74.720 | 37.788 | 62.816 | 69.494 |
| `sort_window` | 2.965 | 117.861 | 52.982 | 75.367 | 36.770 | 66.732 | 74.250 |
| `bloom_filter` | 3.244 | 112.963 | 62.194 | 78.535 | 38.557 | 64.785 | 74.930 |
| `hash_join` | 5.045 | 181.693 | 58.681 | 98.574 | 36.227 | 85.183 | 95.980 |
| `sieve` | 2.710 | 93.667 | 50.449 | 68.306 | 35.943 | 60.651 | 69.430 |
| `fib` | 2.481 | 88.587 | 50.170 | 60.700 | 35.608 | 52.888 | 62.917 |
| `collatz` | 2.624 | 89.070 | 50.795 | 60.671 | 35.387 | 54.117 | 65.155 |
| `matmul` | 2.917 | 95.501 | 52.580 | 69.372 | 35.334 | 71.701 | 78.428 |
| `json_parse` | 40.036 | 457.772 | 123.751 | 99.033 | 36.483 | 135.967 | 123.277 |
| `nbody` | 4.222 | 115.725 | 63.326 | 87.541 | 36.883 | 74.575 | 84.587 |

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
