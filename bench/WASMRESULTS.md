# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T22:11:47Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `f66205c8e321bfcc1f9987f1a26ef0cb30a71d77` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32783189741 |
| NURL | `v0.51.0-3-gf66205c8` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.3 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.431_ | _11.703_ | _8.2_ | _1.529_ | _6.161_ | _4.0_ | _1.624_ | _37.107_ | _22.8_ |
| `lcg` | 39.136 | 66.360 | 1.7 | 39.269 | 64.554 | 1.6 | 39.272 | 75.599 | 1.9 |
| `packet_classifier` | 56.125 | 80.131 | 1.4 | 56.453 | 80.950 | 1.4 | 56.521 | 88.160 | 1.6 |
| `ring_write` | 42.090 | 80.565 | 1.9 | 42.361 | 77.824 | 1.8 | 42.373 | 87.243 | 2.1 |
| `histogram_bins` | 39.543 | 77.398 | 2.0 | 41.484 | 77.316 | 1.9 | 41.455 | 84.112 | 2.0 |
| `prefix_scan` | 21.688 | 39.889 | 1.8 | 21.711 | 40.339 | 1.9 | 21.717 | 47.176 | 2.2 |
| `binary_search` | 40.006 | 89.975 | 2.2 | 38.431 | 92.653 | 2.4 | 38.089 | 99.599 | 2.6 |
| `sort_window` | 27.325 | 71.123 | 2.6 | 27.236 | 57.371 | 2.1 | 26.697 | 68.383 | 2.6 |
| `bloom_filter` | 17.622 | 46.550 | 2.6 | 18.083 | 45.935 | 2.5 | 18.360 | 56.128 | 3.1 |
| `hash_join` | 27.870 | 67.630 | 2.4 | 30.063 | 74.438 | 2.5 | 29.853 | 88.259 | 3.0 |
| `sieve` | 20.749 | 57.120 | 2.8 | 20.895 | 61.706 | 3.0 | 20.550 | 64.089 | 3.1 |
| `fib` | 25.090 | 72.389 | 2.9 | 29.797 | 71.540 | 2.4 | 25.315 | 77.082 | 3.0 |
| `collatz` | 12.261 | 46.973 | 3.8 | 12.305 | 45.537 | 3.7 | 12.402 | 54.387 | 4.4 |
| `matmul` | 33.538 | 57.993 | 1.7 | 33.540 | 51.023 | 1.5 | 33.580 | 62.371 | 1.9 |
| `json_parse` | 8.843 | 48.683 | 5.5 | 8.586 | 40.858 | 4.8 | 11.682 | 64.464 | 5.5 |
| `nbody` | 40.817 | 75.485 | 1.8 | 40.798 | 68.912 | 1.7 | 39.141 | 82.429 | 2.1 |

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
| `packet_classifier` | 1.3 | — | 1.4 | 0.9 |
| `ring_write` | 1.7 | — | 1.8 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.7 | — |
| `binary_search` | 2.0 | — | 2.3 | 1.7 |
| `sort_window` | 2.3 | — | 2.0 | — |
| `bloom_filter` | 2.2 | — | 2.4 | — |
| `hash_join` | 2.1 | — | 2.4 | 1.8 |
| `sieve` | 2.4 | — | 2.9 | — |
| `fib` | 2.6 | — | 2.3 | 1.7 |
| `collatz` | 3.3 | — | 3.7 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.0 | — | 4.9 | — |
| `nbody` | 1.6 | — | 1.6 | 1.2 |

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
| _(floor: empty program)_ | _3.308_ | _0.3_ | _2.3_ | _2.767_ | _3.756_ |
| `lcg` | 42.268 | 0.6 | 1.1 | 42.132 | 43.728 |
| `packet_classifier` | 58.155 | 0.7 | 1.0 | 57.794 | 57.753 |
| `ring_write` | 49.449 | 0.6 | 1.2 | 49.524 | 49.504 |
| `histogram_bins` | 51.206 | 0.7 | 1.3 | 51.157 | 51.218 |
| `prefix_scan` | 16.808 | 0.4 | 0.8 | 16.004 | 16.766 |
| `binary_search` | 100.492 | 1.1 | 2.5 | 99.858 | 128.579 |
| `sort_window` | 103.805 | 1.5 | 3.8 | 119.912 | 120.869 |
| `bloom_filter` | 36.892 | 0.8 | 2.1 | 31.866 | 30.628 |
| `hash_join` | 85.287 | 1.3 | 3.1 | 92.643 | 89.400 |
| `sieve` | 50.137 | 0.9 | 2.4 | 48.057 | 48.470 |
| `fib` | 103.228 | 1.4 | 4.1 | 105.057 | 92.417 |
| `collatz` | 29.233 | 0.6 | 2.4 | 27.832 | 30.496 |
| `matmul` | 34.698 | 0.6 | 1.0 | 37.518 | 38.074 |
| `json_parse` | 71.060 | 1.5 | 8.0 | 31.071 | 119.944 |
| `nbody` | 109.068 | 1.4 | 2.7 | 96.043 | 120.462 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _11.703_ | _142.143_ | _+1115 %_ |
| `lcg` | 1093 | 1394 | +28 % | 66.360 | 176.340 | +166 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 80.131 | 191.553 | +139 % |
| `ring_write` | 1093 | 1394 | +28 % | 80.565 | 190.205 | +136 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 77.398 | 187.671 | +142 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 39.889 | 151.504 | +280 % |
| `binary_search` | 1093 | 1394 | +28 % | 89.975 | 197.410 | +119 % |
| `sort_window` | 1094 | 1395 | +28 % | 71.123 | 177.782 | +150 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 46.550 | 155.693 | +234 % |
| `hash_join` | 1095 | 1397 | +28 % | 67.630 | 183.205 | +171 % |
| `sieve` | 1093 | 1394 | +28 % | 57.120 | 179.055 | +213 % |
| `fib` | 1093 | 1394 | +28 % | 72.389 | 185.946 | +157 % |
| `collatz` | 1093 | 1394 | +28 % | 46.973 | 159.361 | +239 % |
| `matmul` | 1093 | 1394 | +28 % | 57.993 | 166.790 | +188 % |
| `json_parse` | 1119 | 1417 | +27 % | 48.683 | 169.968 | +249 % |
| `nbody` | 1095 | 1396 | +27 % | 75.485 | 187.074 | +148 % |

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
| _(floor: empty program)_ | _30.427_ | _189.777_ | _60.593_ | _58.184_ | _42.157_ | _53.554_ | _68.378_ |
| `lcg` | 2.855 | 98.996 | 61.654 | 66.530 | 41.441 | 59.641 | 74.552 |
| `packet_classifier` | 3.087 | 104.352 | 59.544 | 68.247 | 41.601 | 60.430 | 74.480 |
| `ring_write` | 2.953 | 99.752 | 59.555 | 67.489 | 40.800 | 61.247 | 74.623 |
| `histogram_bins` | 3.132 | 107.154 | 59.777 | 71.099 | 41.551 | 63.063 | 76.499 |
| `prefix_scan` | 3.178 | 106.579 | 60.526 | 71.370 | 42.155 | 63.040 | 77.634 |
| `binary_search` | 3.233 | 106.091 | 63.919 | 69.876 | 41.845 | 67.050 | 79.004 |
| `sort_window` | 3.439 | 114.135 | 62.634 | 74.544 | 40.778 | 71.427 | 84.433 |
| `bloom_filter` | 3.596 | 111.025 | 61.454 | 76.925 | 41.041 | 67.300 | 79.650 |
| `hash_join` | 6.133 | 227.015 | 70.244 | 120.871 | 42.157 | 102.368 | 116.393 |
| `sieve` | 3.187 | 109.528 | 61.625 | 81.047 | 42.852 | 72.489 | 83.151 |
| `fib` | 2.901 | 99.606 | 61.968 | 66.925 | 41.283 | 60.078 | 73.993 |
| `collatz` | 3.105 | 104.549 | 59.094 | 69.071 | 41.392 | 62.786 | 77.153 |
| `matmul` | 3.384 | 109.415 | 63.926 | 79.592 | 41.322 | 84.174 | 92.712 |
| `json_parse` | 52.620 | 603.269 | 146.863 | 122.871 | 41.217 | 167.796 | 149.119 |
| `nbody` | 4.742 | 121.554 | 70.076 | 96.010 | 41.100 | 84.614 | 97.086 |

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
