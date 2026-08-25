# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-25T00:52:16Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16373448 KiB |
| Commit | `af49eb2355dba4de1f157a2d77196918779a5115` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32795148437 |
| NURL | `v0.51.0-8-gaf49eb23` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.5 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.248_ | _10.470_ | _8.4_ | _1.276_ | _6.454_ | _5.1_ | _1.406_ | _29.308_ | _20.8_ |
| `lcg` | 34.344 | 58.037 | 1.7 | 34.371 | 56.545 | 1.6 | 34.593 | 62.399 | 1.8 |
| `packet_classifier` | 49.518 | 69.371 | 1.4 | 49.685 | 67.481 | 1.4 | 49.525 | 72.956 | 1.5 |
| `ring_write` | 37.034 | 69.565 | 1.9 | 37.168 | 66.427 | 1.8 | 37.344 | 73.178 | 2.0 |
| `histogram_bins` | 34.739 | 67.094 | 1.9 | 34.853 | 66.197 | 1.9 | 34.854 | 70.753 | 2.0 |
| `prefix_scan` | 19.132 | 33.990 | 1.8 | 19.224 | 33.659 | 1.8 | 19.362 | 38.780 | 2.0 |
| `binary_search` | 27.751 | 78.294 | 2.8 | 27.953 | 74.398 | 2.7 | 32.021 | 80.629 | 2.5 |
| `sort_window` | 24.063 | 58.597 | 2.4 | 24.031 | 53.302 | 2.2 | 23.665 | 56.249 | 2.4 |
| `bloom_filter` | 15.596 | 40.626 | 2.6 | 15.931 | 42.751 | 2.7 | 16.199 | 43.519 | 2.7 |
| `hash_join` | 22.744 | 59.610 | 2.6 | 24.004 | 59.531 | 2.5 | 24.234 | 70.282 | 2.9 |
| `sieve` | 16.361 | 50.214 | 3.1 | 16.242 | 52.635 | 3.2 | 16.118 | 47.264 | 2.9 |
| `fib` | 21.591 | 62.731 | 2.9 | 25.779 | 57.397 | 2.2 | 21.859 | 62.034 | 2.8 |
| `collatz` | 10.742 | 38.657 | 3.6 | 10.745 | 39.049 | 3.6 | 10.841 | 44.742 | 4.1 |
| `matmul` | 35.584 | 51.981 | 1.5 | 35.842 | 44.432 | 1.2 | 35.472 | 52.179 | 1.5 |
| `json_parse` | 6.982 | 42.534 | 6.1 | 7.189 | 33.597 | 4.7 | 9.323 | 45.369 | 4.9 |
| `nbody` | 35.839 | 59.887 | 1.7 | 35.919 | 58.388 | 1.6 | 34.215 | 66.985 | 2.0 |

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
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.3 | — | 1.5 | — |
| `binary_search` | 2.6 | — | 2.5 | 1.7 |
| `sort_window` | 2.1 | — | 2.1 | — |
| `bloom_filter` | 2.1 | — | 2.5 | — |
| `hash_join` | 2.3 | — | 2.3 | 1.8 |
| `sieve` | 2.6 | — | 3.1 | — |
| `fib` | 2.6 | — | 2.1 | 1.6 |
| `collatz` | 3.0 | — | 3.4 | — |
| `matmul` | 1.2 | — | 1.1 | — |
| `json_parse` | 5.6 | — | 4.6 | — |
| `nbody` | 1.4 | — | 1.5 | 1.1 |

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
| _(floor: empty program)_ | _2.445_ | _0.2_ | _2.0_ | _2.215_ | _2.546_ |
| `lcg` | 36.839 | 0.6 | 1.1 | 36.970 | 36.821 |
| `packet_classifier` | 56.216 | 0.8 | 1.1 | 56.475 | 55.452 |
| `ring_write` | 47.685 | 0.7 | 1.3 | 47.975 | 48.425 |
| `histogram_bins` | 51.446 | 0.8 | 1.5 | 51.419 | 51.576 |
| `prefix_scan` | 12.868 | 0.4 | 0.7 | 13.869 | 12.805 |
| `binary_search` | 73.757 | 0.9 | 2.7 | 66.039 | 89.567 |
| `sort_window` | 62.352 | 1.1 | 2.6 | 69.148 | 69.468 |
| `bloom_filter` | 28.135 | 0.7 | 1.8 | 22.907 | 21.137 |
| `hash_join` | 51.771 | 0.9 | 2.3 | 53.513 | 53.637 |
| `sieve` | 34.281 | 0.7 | 2.1 | 36.437 | 33.657 |
| `fib` | 75.718 | 1.2 | 3.5 | 70.809 | 59.652 |
| `collatz` | 23.202 | 0.6 | 2.2 | 23.820 | 24.045 |
| `matmul` | 26.600 | 0.5 | 0.7 | 28.166 | 28.532 |
| `json_parse` | 38.934 | 0.9 | 5.6 | 18.070 | 91.892 |
| `nbody` | 75.332 | 1.3 | 2.1 | 61.950 | 76.716 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _10.470_ | _108.855_ | _+940 %_ |
| `lcg` | 1093 | 1394 | +28 % | 58.037 | 142.943 | +146 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 69.371 | 154.792 | +123 % |
| `ring_write` | 1093 | 1394 | +28 % | 69.565 | 152.980 | +120 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 67.094 | 152.055 | +127 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 33.990 | 118.104 | +247 % |
| `binary_search` | 1093 | 1394 | +28 % | 78.294 | 155.864 | +99 % |
| `sort_window` | 1094 | 1395 | +28 % | 58.597 | 145.674 | +149 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 40.626 | 125.441 | +209 % |
| `hash_join` | 1095 | 1397 | +28 % | 59.610 | 141.053 | +137 % |
| `sieve` | 1093 | 1394 | +28 % | 50.214 | 134.783 | +168 % |
| `fib` | 1093 | 1394 | +28 % | 62.731 | 142.158 | +127 % |
| `collatz` | 1093 | 1394 | +28 % | 38.657 | 121.920 | +215 % |
| `matmul` | 1093 | 1394 | +28 % | 51.981 | 136.297 | +162 % |
| `json_parse` | 1119 | 1417 | +27 % | 42.534 | 133.799 | +215 % |
| `nbody` | 1095 | 1396 | +27 % | 59.887 | 147.280 | +146 % |

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
| _(floor: empty program)_ | _2.307_ | _83.054_ | _51.787_ | _54.098_ | _36.706_ | _48.681_ | _60.734_ |
| `lcg` | 2.520 | 97.498 | 52.203 | 62.083 | 37.686 | 54.644 | 65.601 |
| `packet_classifier` | 2.627 | 96.697 | 53.904 | 65.606 | 38.647 | 56.122 | 69.534 |
| `ring_write` | 2.804 | 97.630 | 55.476 | 65.041 | 38.487 | 55.853 | 66.242 |
| `histogram_bins` | 2.789 | 101.339 | 54.507 | 69.932 | 38.361 | 58.348 | 69.301 |
| `prefix_scan` | 2.822 | 101.350 | 54.522 | 68.664 | 38.539 | 58.128 | 70.781 |
| `binary_search` | 2.954 | 99.716 | 54.999 | 65.617 | 37.886 | 60.174 | 72.493 |
| `sort_window` | 3.045 | 104.821 | 79.647 | 71.226 | 38.072 | 63.638 | 74.114 |
| `bloom_filter` | 3.130 | 103.479 | 54.964 | 71.055 | 37.948 | 60.073 | 70.610 |
| `hash_join` | 5.202 | 188.367 | 61.826 | 101.134 | 38.133 | 88.617 | 100.168 |
| `sieve` | 2.752 | 97.743 | 54.176 | 68.525 | 58.039 | 61.813 | 72.122 |
| `fib` | 2.540 | 91.136 | 51.014 | 60.756 | 52.182 | 51.598 | 64.723 |
| `collatz` | 2.674 | 93.946 | 52.631 | 63.034 | 39.079 | 55.949 | 67.642 |
| `matmul` | 2.964 | 100.759 | 74.777 | 74.008 | 37.555 | 75.396 | 83.511 |
| `json_parse` | 40.075 | 460.530 | 119.135 | 103.278 | 57.279 | 146.622 | 127.584 |
| `nbody` | 3.988 | 110.581 | 85.671 | 83.674 | 70.464 | 73.696 | 85.376 |

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
