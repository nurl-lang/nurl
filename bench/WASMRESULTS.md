# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-23T15:21:57Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16372432 KiB |
| Commit | `df99c5d3400972df4655d695dc1e37cb145e761e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32648080909 |
| NURL | `v0.49.0-13-gdf99c5d3` |
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
| _(floor: empty program)_ | _1.173_ | _10.165_ | _8.7_ | _1.193_ | _6.282_ | _5.3_ | _1.291_ | _30.993_ | _24.0_ |
| `lcg` | 37.314 | 62.621 | 1.7 | 37.378 | 63.185 | 1.7 | 37.552 | 71.717 | 1.9 |
| `packet_classifier` | 52.525 | 73.867 | 1.4 | 52.690 | 73.243 | 1.4 | 52.891 | 81.211 | 1.5 |
| `ring_write` | 40.394 | 73.344 | 1.8 | 40.494 | 72.279 | 1.8 | 40.842 | 80.643 | 2.0 |
| `histogram_bins` | 40.480 | 74.236 | 1.8 | 40.453 | 71.354 | 1.8 | 40.482 | 82.135 | 2.0 |
| `prefix_scan` | 21.203 | 35.747 | 1.7 | 21.584 | 41.671 | 1.9 | 20.810 | 42.212 | 2.0 |
| `binary_search` | 33.799 | 92.211 | 2.7 | 29.955 | 91.829 | 3.1 | 32.035 | 99.261 | 3.1 |
| `sort_window` | 37.476 | 66.458 | 1.8 | 45.668 | 57.147 | 1.3 | 35.720 | 67.070 | 1.9 |
| `bloom_filter` | 14.013 | 44.726 | 3.2 | 14.367 | 40.865 | 2.8 | 13.792 | 48.017 | 3.5 |
| `hash_join` | 25.907 | 66.195 | 2.6 | 27.891 | 69.037 | 2.5 | 27.873 | 81.913 | 2.9 |
| `sieve` | 31.966 | 70.733 | 2.2 | 32.121 | 74.065 | 2.3 | 31.585 | 73.401 | 2.3 |
| `fib` | 25.774 | 63.983 | 2.5 | 26.550 | 62.976 | 2.4 | 25.627 | 78.299 | 3.1 |
| `collatz` | 12.699 | 44.674 | 3.5 | 12.522 | 46.411 | 3.7 | 12.431 | 53.839 | 4.3 |
| `matmul` | 17.175 | 43.903 | 2.6 | 17.017 | 40.405 | 2.4 | 17.059 | 51.307 | 3.0 |
| `json_parse` | 7.600 | 46.860 | 6.2 | 7.334 | 37.763 | 5.1 | 9.505 | 54.473 | 5.7 |
| `nbody` | 36.030 | 66.599 | 1.8 | 36.044 | 61.344 | 1.7 | 33.455 | 72.836 | 2.2 |

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
| `lcg` | 1.5 | — | 1.6 | 1.1 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.6 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.6 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.7 | — |
| `binary_search` | 2.5 | — | 3.0 | 2.2 |
| `sort_window` | 1.6 | — | 1.1 | 1.0 |
| `bloom_filter` | 2.7 | — | 2.6 | — |
| `hash_join` | 2.3 | — | 2.4 | 1.9 |
| `sieve` | 2.0 | — | 2.2 | 1.4 |
| `fib` | 2.2 | — | 2.2 | 1.9 |
| `collatz` | 3.0 | — | 3.5 | — |
| `matmul` | 2.1 | — | 2.2 | — |
| `json_parse` | 5.7 | — | 5.1 | — |
| `nbody` | 1.6 | — | 1.6 | 1.3 |

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
| _(floor: empty program)_ | _1.664_ | _0.2_ | _1.4_ | _1.789_ | _1.972_ |
| `lcg` | 168.486 | 2.7 | 4.5 | 168.081 | 169.046 |
| `packet_classifier` | 338.030 | 4.6 | 6.4 | 338.092 | 342.518 |
| `ring_write` | 376.219 | 5.1 | 9.3 | 375.185 | 364.823 |
| `histogram_bins` | 482.044 | 6.5 | 11.9 | 516.080 | 482.038 |
| `prefix_scan` | 122.713 | 3.4 | 5.8 | 115.692 | 123.540 |
| `binary_search` | 977.611 | 10.6 | 28.9 | 968.427 | 1144.383 |
| `sort_window` | 618.549 | 9.3 | 16.5 | 351.101 | 352.969 |
| `bloom_filter` | 239.608 | 5.4 | 17.1 | 273.058 | 239.026 |
| `hash_join` | 964.029 | 14.6 | 37.2 | 995.928 | 1003.407 |
| `sieve` | 432.505 | 6.1 | 13.5 | 439.784 | 349.630 |
| `fib` | 704.753 | 11.0 | 27.3 | 687.172 | 667.544 |
| `collatz` | 192.316 | 4.3 | 15.1 | 181.007 | 181.249 |
| `matmul` | 223.196 | 5.1 | 13.0 | 235.634 | 231.750 |
| `json_parse` | 299.710 | 6.4 | 39.4 | 135.662 | 236.097 |
| `nbody` | 635.930 | 9.5 | 17.7 | 633.990 | 673.825 |

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
| _(floor: empty program)_ | _1072_ | _1392_ | _+30 %_ | _10.165_ | _135.979_ | _+1238 %_ |
| `lcg` | 1092 | 1392 | +28 % | 62.621 | 168.399 | +169 % |
| `packet_classifier` | 1091 | 1392 | +28 % | 73.867 | 181.822 | +146 % |
| `ring_write` | 1092 | 1392 | +28 % | 73.344 | 178.291 | +143 % |
| `histogram_bins` | 1092 | 1392 | +28 % | 74.236 | 180.659 | +143 % |
| `prefix_scan` | 1092 | 1392 | +28 % | 35.747 | 149.007 | +317 % |
| `binary_search` | 1092 | 1392 | +28 % | 92.211 | 194.420 | +111 % |
| `sort_window` | 1092 | 1393 | +28 % | 66.458 | 176.562 | +166 % |
| `bloom_filter` | 1092 | 1393 | +28 % | 44.726 | 152.784 | +242 % |
| `hash_join` | 1094 | 1395 | +28 % | 66.195 | 173.412 | +162 % |
| `sieve` | 1092 | 1392 | +28 % | 70.733 | 176.337 | +149 % |
| `fib` | 1091 | 1392 | +28 % | 63.983 | 173.406 | +171 % |
| `collatz` | 1091 | 1392 | +28 % | 44.674 | 152.816 | +242 % |
| `matmul` | 1092 | 1392 | +28 % | 43.903 | 154.992 | +253 % |
| `json_parse` | 1117 | 1415 | +27 % | 46.860 | 156.022 | +233 % |
| `nbody` | 1093 | 1394 | +27 % | 66.599 | 178.214 | +168 % |

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
| _(floor: empty program)_ | _2.220_ | _80.315_ | _47.170_ | _50.067_ | _31.697_ | _49.564_ | _62.303_ |
| `lcg` | 2.362 | 86.961 | 61.391 | 57.788 | 32.293 | 55.787 | 69.131 |
| `packet_classifier` | 2.430 | 88.401 | 47.547 | 58.277 | 32.447 | 55.424 | 68.418 |
| `ring_write` | 2.583 | 90.846 | 47.477 | 60.612 | 33.624 | 57.028 | 69.903 |
| `histogram_bins` | 2.639 | 92.512 | 49.661 | 61.273 | 33.111 | 61.022 | 70.600 |
| `prefix_scan` | 2.623 | 93.967 | 47.870 | 61.952 | 33.206 | 58.948 | 72.226 |
| `binary_search` | 2.767 | 93.288 | 48.556 | 59.262 | 33.697 | 61.435 | 75.375 |
| `sort_window` | 2.849 | 100.042 | 47.996 | 67.100 | 33.168 | 66.034 | 79.018 |
| `bloom_filter` | 3.061 | 100.450 | 48.857 | 68.465 | 33.608 | 63.134 | 75.053 |
| `hash_join` | 5.339 | 202.121 | 54.844 | 104.406 | 34.279 | 96.148 | 110.028 |
| `sieve` | 2.676 | 93.022 | 48.279 | 67.757 | 33.557 | 67.871 | 76.913 |
| `fib` | 2.412 | 86.937 | 62.740 | 57.301 | 32.804 | 55.045 | 67.945 |
| `collatz` | 2.572 | 90.986 | 47.775 | 58.562 | 34.258 | 57.980 | 70.783 |
| `matmul` | 2.999 | 100.150 | 54.624 | 70.131 | 32.996 | 79.690 | 87.902 |
| `json_parse` | 49.094 | 535.241 | 145.632 | 107.149 | 32.862 | 162.721 | 142.879 |
| `nbody` | 4.055 | 110.078 | 54.792 | 85.299 | 33.579 | 81.602 | 92.613 |

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
