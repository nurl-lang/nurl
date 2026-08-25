# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-25T02:35:58Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `7b2654d566ca73b4d75e8a4b160b66a381d5e429` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32801797187 |
| NURL | `v0.51.0-13-g7b2654d5` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.7 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.442_ | _11.827_ | _8.2_ | _1.511_ | _6.864_ | _4.5_ | _1.644_ | _37.515_ | _22.8_ |
| `lcg` | 39.194 | 67.270 | 1.7 | 39.254 | 66.293 | 1.7 | 39.458 | 75.493 | 1.9 |
| `packet_classifier` | 56.322 | 80.362 | 1.4 | 56.558 | 79.707 | 1.4 | 56.496 | 87.820 | 1.6 |
| `ring_write` | 42.101 | 78.455 | 1.9 | 42.223 | 77.078 | 1.8 | 42.349 | 86.910 | 2.1 |
| `histogram_bins` | 39.379 | 78.951 | 2.0 | 41.113 | 76.141 | 1.9 | 41.243 | 84.945 | 2.1 |
| `prefix_scan` | 21.602 | 39.029 | 1.8 | 21.762 | 40.942 | 1.9 | 21.839 | 46.510 | 2.1 |
| `binary_search` | 39.720 | 88.951 | 2.2 | 38.178 | 93.454 | 2.4 | 38.220 | 103.426 | 2.7 |
| `sort_window` | 27.121 | 77.698 | 2.9 | 27.349 | 61.252 | 2.2 | 26.725 | 71.632 | 2.7 |
| `bloom_filter` | 17.510 | 46.606 | 2.7 | 18.133 | 45.166 | 2.5 | 18.339 | 52.153 | 2.8 |
| `hash_join` | 27.886 | 69.593 | 2.5 | 30.191 | 81.058 | 2.7 | 29.960 | 90.606 | 3.0 |
| `sieve` | 19.859 | 58.028 | 2.9 | 19.827 | 67.191 | 3.4 | 20.111 | 61.100 | 3.0 |
| `fib` | 25.060 | 78.127 | 3.1 | 29.890 | 72.545 | 2.4 | 25.158 | 87.824 | 3.5 |
| `collatz` | 12.303 | 47.454 | 3.9 | 12.245 | 46.050 | 3.8 | 12.431 | 55.546 | 4.5 |
| `matmul` | 33.535 | 57.305 | 1.7 | 33.406 | 54.276 | 1.6 | 33.556 | 61.605 | 1.8 |
| `json_parse` | 8.852 | 52.703 | 6.0 | 8.666 | 40.280 | 4.6 | 11.611 | 58.142 | 5.0 |
| `nbody` | 40.806 | 79.432 | 1.9 | 40.825 | 68.353 | 1.7 | 38.781 | 80.159 | 2.1 |

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
| `lcg` | 1.5 | — | 1.6 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.8 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.3 | — | 1.7 | — |
| `binary_search` | 2.0 | — | 2.4 | 1.8 |
| `sort_window` | 2.6 | — | 2.1 | — |
| `bloom_filter` | 2.2 | — | 2.3 | — |
| `hash_join` | 2.2 | — | 2.6 | 1.9 |
| `sieve` | 2.5 | — | 3.3 | — |
| `fib` | 2.8 | — | 2.3 | 2.1 |
| `collatz` | 3.3 | — | 3.7 | — |
| `matmul` | 1.4 | — | 1.5 | — |
| `json_parse` | 5.5 | — | 4.7 | — |
| `nbody` | 1.7 | — | 1.6 | 1.1 |

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
| _(floor: empty program)_ | _3.100_ | _0.3_ | _2.1_ | _2.912_ | _3.746_ |
| `lcg` | 42.660 | 0.6 | 1.1 | 42.199 | 42.754 |
| `packet_classifier` | 64.695 | 0.8 | 1.1 | 64.647 | 66.030 |
| `ring_write` | 55.383 | 0.7 | 1.3 | 55.091 | 57.527 |
| `histogram_bins` | 56.583 | 0.7 | 1.4 | 59.771 | 57.876 |
| `prefix_scan` | 15.682 | 0.4 | 0.7 | 15.988 | 14.705 |
| `binary_search` | 76.207 | 0.9 | 1.9 | 75.965 | 102.229 |
| `sort_window` | 101.158 | 1.3 | 3.7 | 110.365 | 104.680 |
| `bloom_filter` | 25.511 | 0.5 | 1.5 | 27.654 | 24.892 |
| `hash_join` | 66.337 | 1.0 | 2.4 | 83.213 | 87.021 |
| `sieve` | 43.401 | 0.7 | 2.2 | 42.579 | 38.691 |
| `fib` | 86.433 | 1.1 | 3.4 | 82.041 | 73.509 |
| `collatz` | 28.234 | 0.6 | 2.3 | 28.047 | 28.265 |
| `matmul` | 33.904 | 0.6 | 1.0 | 37.735 | 37.081 |
| `json_parse` | 52.014 | 1.0 | 5.9 | 23.970 | 108.673 |
| `nbody` | 96.854 | 1.2 | 2.4 | 88.834 | 103.562 |

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
| `binary_search` | 16 | 1094 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1094 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1094 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1096 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1093 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1094 | 16 | 917 | 4403 | 2084 |
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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _11.827_ | _143.608_ | _+1114 %_ |
| `lcg` | 1093 | 1395 | +28 % | 67.270 | 179.424 | +167 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 80.362 | 189.641 | +136 % |
| `ring_write` | 1093 | 1395 | +28 % | 78.455 | 190.296 | +143 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 78.951 | 189.880 | +141 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 39.029 | 149.839 | +284 % |
| `binary_search` | 1094 | 1395 | +28 % | 88.951 | 201.232 | +126 % |
| `sort_window` | 1094 | 1395 | +28 % | 77.698 | 186.809 | +140 % |
| `bloom_filter` | 1094 | 1395 | +28 % | 46.606 | 158.076 | +239 % |
| `hash_join` | 1096 | 1398 | +28 % | 69.593 | 180.093 | +159 % |
| `sieve` | 1093 | 1395 | +28 % | 58.028 | 180.566 | +211 % |
| `fib` | 1093 | 1394 | +28 % | 78.127 | 187.808 | +140 % |
| `collatz` | 1093 | 1395 | +28 % | 47.454 | 163.045 | +244 % |
| `matmul` | 1094 | 1395 | +28 % | 57.305 | 170.313 | +197 % |
| `json_parse` | 1119 | 1418 | +27 % | 52.703 | 166.617 | +216 % |
| `nbody` | 1095 | 1396 | +27 % | 79.432 | 188.834 | +138 % |

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
| _(floor: empty program)_ | _2.677_ | _94.484_ | _58.689_ | _57.295_ | _41.561_ | _54.906_ | _67.968_ |
| `lcg` | 2.882 | 102.972 | 63.467 | 68.293 | 42.626 | 62.122 | 75.931 |
| `packet_classifier` | 2.903 | 104.976 | 60.796 | 70.029 | 43.128 | 60.489 | 75.710 |
| `ring_write` | 2.973 | 103.030 | 60.518 | 69.027 | 42.310 | 62.605 | 75.487 |
| `histogram_bins` | 3.066 | 105.410 | 59.052 | 69.319 | 41.614 | 62.864 | 77.400 |
| `prefix_scan` | 3.070 | 108.435 | 60.761 | 73.150 | 41.800 | 63.522 | 78.326 |
| `binary_search` | 3.319 | 107.178 | 60.559 | 70.142 | 41.637 | 67.219 | 79.626 |
| `sort_window` | 3.293 | 112.460 | 60.866 | 75.356 | 41.552 | 70.413 | 84.727 |
| `bloom_filter` | 3.591 | 113.794 | 61.254 | 77.362 | 41.035 | 66.921 | 80.734 |
| `hash_join` | 6.094 | 231.277 | 70.434 | 120.828 | 42.875 | 102.860 | 116.449 |
| `sieve` | 3.131 | 108.315 | 60.517 | 78.129 | 41.445 | 71.258 | 82.179 |
| `fib` | 2.839 | 99.607 | 58.879 | 66.186 | 41.283 | 60.322 | 74.267 |
| `collatz` | 2.999 | 103.494 | 60.319 | 67.618 | 42.612 | 63.300 | 76.892 |
| `matmul` | 3.412 | 113.754 | 65.391 | 82.239 | 44.953 | 86.276 | 99.035 |
| `json_parse` | 53.134 | 612.787 | 147.651 | 125.713 | 42.511 | 170.289 | 153.400 |
| `nbody` | 4.689 | 124.686 | 69.152 | 96.222 | 42.999 | 87.019 | 98.235 |

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
