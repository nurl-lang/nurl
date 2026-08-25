# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-25T02:06:43Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16373448 KiB |
| Commit | `1165737f4cfa3ee4406a8cecf33f58b9b8e6c486` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32799900340 |
| NURL | `v0.51.0-10-g1165737f` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.6 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.459_ | _11.921_ | _8.2_ | _1.544_ | _8.146_ | _5.3_ | _1.724_ | _36.370_ | _21.1_ |
| `lcg` | 39.178 | 68.043 | 1.7 | 39.312 | 65.511 | 1.7 | 39.443 | 75.393 | 1.9 |
| `packet_classifier` | 56.220 | 79.973 | 1.4 | 56.491 | 78.758 | 1.4 | 56.544 | 88.217 | 1.6 |
| `ring_write` | 42.256 | 80.252 | 1.9 | 42.385 | 78.915 | 1.9 | 42.610 | 86.974 | 2.0 |
| `histogram_bins` | 39.595 | 78.408 | 2.0 | 41.330 | 76.568 | 1.9 | 41.477 | 85.094 | 2.1 |
| `prefix_scan` | 21.612 | 42.505 | 2.0 | 21.895 | 37.313 | 1.7 | 21.874 | 47.808 | 2.2 |
| `binary_search` | 39.883 | 91.135 | 2.3 | 38.498 | 94.531 | 2.5 | 38.274 | 101.819 | 2.7 |
| `sort_window` | 27.406 | 77.575 | 2.8 | 27.607 | 57.587 | 2.1 | 26.982 | 68.491 | 2.5 |
| `bloom_filter` | 17.545 | 52.965 | 3.0 | 18.324 | 45.200 | 2.5 | 18.476 | 52.824 | 2.9 |
| `hash_join` | 28.108 | 68.199 | 2.4 | 30.365 | 73.352 | 2.4 | 30.209 | 81.676 | 2.7 |
| `sieve` | 21.285 | 59.403 | 2.8 | 20.428 | 64.280 | 3.1 | 20.793 | 62.255 | 3.0 |
| `fib` | 25.400 | 71.564 | 2.8 | 30.164 | 72.535 | 2.4 | 25.559 | 76.459 | 3.0 |
| `collatz` | 12.271 | 49.611 | 4.0 | 12.316 | 46.888 | 3.8 | 12.460 | 53.461 | 4.3 |
| `matmul` | 33.863 | 57.139 | 1.7 | 33.863 | 52.625 | 1.6 | 33.915 | 63.781 | 1.9 |
| `json_parse` | 9.150 | 57.803 | 6.3 | 8.857 | 40.862 | 4.6 | 11.828 | 64.570 | 5.5 |
| `nbody` | 40.879 | 77.580 | 1.9 | 40.969 | 71.189 | 1.7 | 39.151 | 82.740 | 2.1 |

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
| `ring_write` | 1.7 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.5 | — | 1.4 | — |
| `binary_search` | 2.1 | — | 2.3 | 1.8 |
| `sort_window` | 2.5 | — | 1.9 | — |
| `bloom_filter` | 2.6 | — | 2.2 | — |
| `hash_join` | 2.1 | — | 2.3 | 1.6 |
| `sieve` | 2.4 | — | 3.0 | — |
| `fib` | 2.5 | — | 2.2 | 1.7 |
| `collatz` | 3.5 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 6.0 | — | 4.5 | — |
| `nbody` | 1.7 | — | 1.6 | 1.2 |

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
| _(floor: empty program)_ | _3.291_ | _0.3_ | _2.3_ | _3.028_ | _3.520_ |
| `lcg` | 42.202 | 0.6 | 1.1 | 42.779 | 42.715 |
| `packet_classifier` | 65.735 | 0.8 | 1.2 | 64.613 | 67.626 |
| `ring_write` | 55.124 | 0.7 | 1.3 | 56.361 | 55.516 |
| `histogram_bins` | 61.651 | 0.8 | 1.6 | 57.607 | 61.715 |
| `prefix_scan` | 14.005 | 0.3 | 0.6 | 16.148 | 14.435 |
| `binary_search` | 79.780 | 0.9 | 2.0 | 78.278 | 107.543 |
| `sort_window` | 101.599 | 1.3 | 3.7 | 120.887 | 119.432 |
| `bloom_filter` | 24.555 | 0.5 | 1.4 | 33.750 | 26.762 |
| `hash_join` | 82.559 | 1.2 | 2.9 | 84.753 | 85.714 |
| `sieve` | 55.858 | 0.9 | 2.6 | 51.180 | 46.670 |
| `fib` | 94.511 | 1.3 | 3.7 | 89.157 | 73.476 |
| `collatz` | 27.197 | 0.5 | 2.2 | 28.046 | 31.452 |
| `matmul` | 36.707 | 0.6 | 1.1 | 40.925 | 37.682 |
| `json_parse` | 51.185 | 0.9 | 5.6 | 24.296 | 105.523 |
| `nbody` | 108.024 | 1.4 | 2.6 | 88.443 | 110.617 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _11.921_ | _144.918_ | _+1116 %_ |
| `lcg` | 1093 | 1395 | +28 % | 68.043 | 181.230 | +166 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 79.973 | 193.620 | +142 % |
| `ring_write` | 1093 | 1395 | +28 % | 80.252 | 190.333 | +137 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 78.408 | 188.788 | +141 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 42.505 | 149.990 | +253 % |
| `binary_search` | 1094 | 1395 | +28 % | 91.135 | 200.944 | +120 % |
| `sort_window` | 1094 | 1395 | +28 % | 77.575 | 181.213 | +134 % |
| `bloom_filter` | 1094 | 1395 | +28 % | 52.965 | 158.007 | +198 % |
| `hash_join` | 1096 | 1398 | +28 % | 68.199 | 179.614 | +163 % |
| `sieve` | 1093 | 1395 | +28 % | 59.403 | 177.094 | +198 % |
| `fib` | 1093 | 1394 | +28 % | 71.564 | 183.430 | +156 % |
| `collatz` | 1093 | 1395 | +28 % | 49.611 | 158.545 | +220 % |
| `matmul` | 1094 | 1395 | +28 % | 57.139 | 170.408 | +198 % |
| `json_parse` | 1119 | 1418 | +27 % | 57.803 | 165.342 | +186 % |
| `nbody` | 1095 | 1396 | +27 % | 77.580 | 189.961 | +145 % |

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
| _(floor: empty program)_ | _2.678_ | _96.446_ | _62.091_ | _58.433_ | _42.548_ | _54.627_ | _69.747_ |
| `lcg` | 2.916 | 103.272 | 64.449 | 67.903 | 41.590 | 61.901 | 75.175 |
| `packet_classifier` | 2.903 | 105.601 | 59.991 | 73.429 | 43.578 | 60.710 | 75.583 |
| `ring_write` | 3.006 | 104.534 | 60.878 | 68.746 | 43.565 | 61.612 | 77.791 |
| `histogram_bins` | 3.063 | 106.387 | 60.757 | 71.334 | 42.284 | 64.559 | 77.666 |
| `prefix_scan` | 3.145 | 108.435 | 59.867 | 73.956 | 41.724 | 63.648 | 79.030 |
| `binary_search` | 3.356 | 109.040 | 61.304 | 69.589 | 42.319 | 67.453 | 82.002 |
| `sort_window` | 3.361 | 115.965 | 63.848 | 77.955 | 44.312 | 72.774 | 85.757 |
| `bloom_filter` | 3.520 | 112.494 | 63.287 | 77.108 | 44.106 | 68.410 | 81.839 |
| `hash_join` | 6.198 | 235.563 | 71.129 | 123.083 | 43.483 | 103.475 | 118.586 |
| `sieve` | 3.264 | 114.107 | 62.529 | 80.930 | 42.265 | 73.282 | 82.910 |
| `fib` | 2.886 | 101.556 | 59.040 | 68.989 | 41.634 | 59.157 | 75.457 |
| `collatz` | 3.110 | 105.846 | 62.887 | 69.348 | 42.254 | 63.887 | 76.982 |
| `matmul` | 3.404 | 114.466 | 63.987 | 82.081 | 43.985 | 85.518 | 97.510 |
| `json_parse` | 53.291 | 626.038 | 149.406 | 128.463 | 43.992 | 175.317 | 153.500 |
| `nbody` | 4.875 | 129.145 | 71.040 | 99.064 | 42.883 | 87.642 | 99.797 |

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
