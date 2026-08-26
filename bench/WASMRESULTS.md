# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-26T20:52:45Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `f217409f5fe94c55fac1de73ca8678043b356706` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33012367280 |
| NURL | `v0.53.0-1-gf217409f` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
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
| _(floor: empty program)_ | _1.238_ | _9.157_ | _7.4_ | _1.266_ | _6.021_ | _4.8_ | _1.428_ | _29.392_ | _20.6_ |
| `lcg` | 34.723 | 59.522 | 1.7 | 34.427 | 58.207 | 1.7 | 34.655 | 64.307 | 1.9 |
| `packet_classifier` | 49.992 | 70.791 | 1.4 | 50.941 | 68.584 | 1.3 | 49.510 | 74.287 | 1.5 |
| `ring_write` | 37.804 | 70.476 | 1.9 | 38.520 | 69.921 | 1.8 | 38.694 | 74.880 | 1.9 |
| `histogram_bins` | 35.130 | 69.195 | 2.0 | 35.488 | 66.725 | 1.9 | 34.887 | 72.214 | 2.1 |
| `prefix_scan` | 19.331 | 33.937 | 1.8 | 19.710 | 31.938 | 1.6 | 19.210 | 38.641 | 2.0 |
| `binary_search` | 27.716 | 77.456 | 2.8 | 28.478 | 78.411 | 2.8 | 32.101 | 81.962 | 2.6 |
| `sort_window` | 24.443 | 60.658 | 2.5 | 24.320 | 51.297 | 2.1 | 23.854 | 57.394 | 2.4 |
| `bloom_filter` | 15.759 | 40.025 | 2.5 | 15.993 | 39.759 | 2.5 | 16.108 | 44.075 | 2.7 |
| `hash_join` | 23.006 | 58.565 | 2.5 | 23.976 | 78.891 | 3.3 | 24.919 | 68.265 | 2.7 |
| `sieve` | 16.227 | 49.456 | 3.0 | 15.672 | 55.675 | 3.6 | 16.189 | 49.175 | 3.0 |
| `fib` | 22.487 | 58.881 | 2.6 | 26.098 | 59.207 | 2.3 | 22.296 | 64.226 | 2.9 |
| `collatz` | 10.737 | 40.666 | 3.8 | 10.777 | 39.148 | 3.6 | 10.986 | 44.682 | 4.1 |
| `matmul` | 36.508 | 55.312 | 1.5 | 36.311 | 45.241 | 1.2 | 36.748 | 52.533 | 1.4 |
| `json_parse` | 6.813 | 41.383 | 6.1 | 7.131 | 34.191 | 4.8 | 9.669 | 46.614 | 4.8 |
| `nbody` | 36.921 | 61.144 | 1.7 | 36.761 | 62.521 | 1.7 | 35.051 | 68.855 | 2.0 |

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
| `packet_classifier` | 1.3 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.8 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.4 | — | 1.4 | — |
| `binary_search` | 2.6 | — | 2.7 | 1.7 |
| `sort_window` | 2.2 | — | 2.0 | — |
| `bloom_filter` | 2.1 | — | 2.3 | — |
| `hash_join` | 2.3 | — | 3.2 | 1.7 |
| `sieve` | 2.7 | — | 3.4 | — |
| `fib` | 2.3 | — | 2.1 | 1.7 |
| `collatz` | 3.3 | — | 3.5 | — |
| `matmul` | 1.3 | — | 1.1 | — |
| `json_parse` | 5.8 | — | 4.8 | — |
| `nbody` | 1.5 | — | 1.6 | 1.2 |

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
| _(floor: empty program)_ | _2.275_ | _0.2_ | _1.8_ | _2.404_ | _2.502_ |
| `lcg` | 37.175 | 0.6 | 1.1 | 36.811 | 36.871 |
| `packet_classifier` | 54.227 | 0.8 | 1.1 | 53.713 | 55.140 |
| `ring_write` | 49.643 | 0.7 | 1.3 | 50.117 | 49.421 |
| `histogram_bins` | 49.663 | 0.7 | 1.4 | 58.418 | 52.687 |
| `prefix_scan` | 11.726 | 0.3 | 0.6 | 13.635 | 12.288 |
| `binary_search` | 57.590 | 0.7 | 2.1 | 62.390 | 86.830 |
| `sort_window` | 62.813 | 1.0 | 2.6 | 52.513 | 55.439 |
| `bloom_filter` | 20.965 | 0.5 | 1.3 | 22.477 | 21.799 |
| `hash_join` | 51.684 | 0.9 | 2.2 | 54.777 | 54.159 |
| `sieve` | 34.553 | 0.7 | 2.1 | 34.167 | 31.149 |
| `fib` | 64.721 | 1.1 | 2.9 | 59.794 | 51.591 |
| `collatz` | 24.077 | 0.6 | 2.2 | 24.105 | 23.634 |
| `matmul` | 25.262 | 0.5 | 0.7 | 29.814 | 29.439 |
| `json_parse` | 36.411 | 0.9 | 5.3 | 22.527 | 75.668 |
| `nbody` | 77.830 | 1.3 | 2.1 | 62.870 | 76.553 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _9.157_ | _113.482_ | _+1139 %_ |
| `lcg` | 1093 | 1395 | +28 % | 59.522 | 146.251 | +146 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 70.791 | 156.267 | +121 % |
| `ring_write` | 1093 | 1395 | +28 % | 70.476 | 158.266 | +125 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 69.195 | 154.313 | +123 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 33.937 | 117.998 | +248 % |
| `binary_search` | 1094 | 1395 | +28 % | 77.456 | 165.414 | +114 % |
| `sort_window` | 1094 | 1395 | +28 % | 60.658 | 146.693 | +142 % |
| `bloom_filter` | 1094 | 1395 | +28 % | 40.025 | 129.369 | +223 % |
| `hash_join` | 1096 | 1398 | +28 % | 58.565 | 142.120 | +143 % |
| `sieve` | 1093 | 1395 | +28 % | 49.456 | 144.420 | +192 % |
| `fib` | 1093 | 1394 | +28 % | 58.881 | 145.109 | +146 % |
| `collatz` | 1093 | 1395 | +28 % | 40.666 | 126.263 | +210 % |
| `matmul` | 1094 | 1395 | +28 % | 55.312 | 139.774 | +153 % |
| `json_parse` | 1119 | 1418 | +27 % | 41.383 | 133.368 | +222 % |
| `nbody` | 1095 | 1396 | +27 % | 61.144 | 148.746 | +143 % |

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
| _(floor: empty program)_ | _2.424_ | _86.795_ | _53.035_ | _55.852_ | _37.096_ | _49.252_ | _60.361_ |
| `lcg` | 53.963 | 225.234 | 93.334 | 116.761 | 56.935 | 55.003 | 67.064 |
| `packet_classifier` | 2.737 | 96.000 | 56.144 | 63.142 | 37.921 | 54.347 | 67.339 |
| `ring_write` | 2.689 | 95.337 | 54.167 | 65.348 | 37.732 | 56.081 | 68.206 |
| `histogram_bins` | 2.842 | 97.297 | 52.953 | 65.965 | 37.500 | 58.421 | 68.267 |
| `prefix_scan` | 2.856 | 99.596 | 54.311 | 67.074 | 38.217 | 58.401 | 70.231 |
| `binary_search` | 2.974 | 97.555 | 54.598 | 64.333 | 38.764 | 60.684 | 72.418 |
| `sort_window` | 3.024 | 104.975 | 55.497 | 69.440 | 38.329 | 63.448 | 75.815 |
| `bloom_filter` | 3.201 | 99.837 | 56.084 | 69.448 | 37.438 | 59.573 | 71.739 |
| `hash_join` | 5.185 | 186.774 | 59.835 | 101.264 | 39.026 | 89.518 | 100.187 |
| `sieve` | 2.930 | 97.122 | 53.503 | 71.751 | 38.405 | 63.885 | 73.520 |
| `fib` | 2.606 | 92.622 | 52.326 | 62.238 | 39.091 | 54.080 | 66.310 |
| `collatz` | 2.809 | 94.547 | 51.805 | 64.156 | 37.189 | 56.857 | 68.117 |
| `matmul` | 3.105 | 101.738 | 55.015 | 74.212 | 37.287 | 74.506 | 81.604 |
| `json_parse` | 42.664 | 474.971 | 123.720 | 106.980 | 38.810 | 142.690 | 128.475 |
| `nbody` | 4.134 | 109.439 | 60.487 | 85.553 | 38.838 | 77.673 | 86.599 |

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
