# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-29T13:28:47Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `900a240928022084e35cb856078748bc34f5cd51` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33254991702 |
| NURL | `v0.55.0-6-g900a2409` |
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
| _(floor: empty program)_ | _1.427_ | _10.412_ | _7.3_ | _1.514_ | _6.178_ | _4.1_ | _1.639_ | _36.991_ | _22.6_ |
| `lcg` | 39.157 | 65.586 | 1.7 | 39.020 | 64.632 | 1.7 | 39.111 | 73.337 | 1.9 |
| `packet_classifier` | 56.191 | 78.623 | 1.4 | 56.359 | 78.498 | 1.4 | 56.384 | 86.614 | 1.5 |
| `ring_write` | 42.003 | 78.121 | 1.9 | 42.118 | 77.566 | 1.8 | 42.383 | 86.089 | 2.0 |
| `histogram_bins` | 39.611 | 81.262 | 2.1 | 41.161 | 75.457 | 1.8 | 41.310 | 84.257 | 2.0 |
| `prefix_scan` | 21.642 | 39.397 | 1.8 | 21.711 | 38.004 | 1.8 | 21.734 | 46.397 | 2.1 |
| `binary_search` | 38.201 | 89.781 | 2.4 | 38.222 | 90.975 | 2.4 | 38.162 | 99.236 | 2.6 |
| `sort_window` | 27.286 | 69.813 | 2.6 | 27.256 | 59.118 | 2.2 | 26.772 | 66.615 | 2.5 |
| `bloom_filter` | 17.464 | 51.402 | 2.9 | 18.042 | 50.680 | 2.8 | 18.340 | 61.885 | 3.4 |
| `hash_join` | 27.903 | 67.511 | 2.4 | 30.226 | 73.395 | 2.4 | 29.999 | 82.046 | 2.7 |
| `sieve` | 20.058 | 60.193 | 3.0 | 18.045 | 59.689 | 3.3 | 18.229 | 59.168 | 3.2 |
| `fib` | 25.233 | 71.236 | 2.8 | 30.275 | 78.186 | 2.6 | 25.613 | 81.829 | 3.2 |
| `collatz` | 12.318 | 46.318 | 3.8 | 12.303 | 47.635 | 3.9 | 12.357 | 54.855 | 4.4 |
| `matmul` | 33.764 | 58.074 | 1.7 | 33.605 | 53.879 | 1.6 | 33.868 | 64.818 | 1.9 |
| `json_parse` | 8.779 | 49.248 | 5.6 | 8.665 | 39.649 | 4.6 | 11.732 | 60.448 | 5.2 |
| `nbody` | 40.713 | 78.466 | 1.9 | 40.820 | 71.861 | 1.8 | 39.108 | 86.213 | 2.2 |

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
| `lcg` | 1.5 | — | 1.6 | — |
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.8 | 1.2 |
| `histogram_bins` | 1.9 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.6 | — |
| `binary_search` | 2.2 | — | 2.3 | 1.7 |
| `sort_window` | 2.3 | — | 2.1 | — |
| `bloom_filter` | 2.6 | — | 2.7 | — |
| `hash_join` | 2.2 | — | 2.3 | 1.6 |
| `sieve` | 2.7 | — | 3.2 | — |
| `fib` | 2.6 | — | 2.5 | 1.9 |
| `collatz` | 3.3 | — | 3.8 | — |
| `matmul` | 1.5 | — | 1.5 | — |
| `json_parse` | 5.3 | — | 4.7 | — |
| `nbody` | 1.7 | — | 1.7 | 1.3 |

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
| _(floor: empty program)_ | _3.040_ | _0.3_ | _2.1_ | _2.784_ | _3.567_ |
| `lcg` | 41.760 | 0.6 | 1.1 | 42.352 | 42.576 |
| `packet_classifier` | 61.124 | 0.8 | 1.1 | 62.249 | 63.555 |
| `ring_write` | 54.138 | 0.7 | 1.3 | 56.099 | 55.465 |
| `histogram_bins` | 55.481 | 0.7 | 1.4 | 59.061 | 61.337 |
| `prefix_scan` | 13.108 | 0.3 | 0.6 | 15.631 | 14.281 |
| `binary_search` | 66.710 | 0.7 | 1.7 | 69.381 | 101.902 |
| `sort_window` | 99.736 | 1.4 | 3.7 | 88.553 | 83.858 |
| `bloom_filter` | 23.005 | 0.4 | 1.3 | 25.969 | 24.552 |
| `hash_join` | 66.723 | 1.0 | 2.4 | 83.273 | 87.279 |
| `sieve` | 48.980 | 0.8 | 2.4 | 42.917 | 41.945 |
| `fib` | 75.876 | 1.1 | 3.0 | 73.923 | 74.747 |
| `collatz` | 27.160 | 0.6 | 2.2 | 27.286 | 27.774 |
| `matmul` | 31.326 | 0.5 | 0.9 | 36.300 | 36.943 |
| `json_parse` | 48.177 | 1.0 | 5.5 | 24.019 | 107.284 |
| `nbody` | 96.428 | 1.2 | 2.4 | 88.643 | 102.169 |

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
| `lcg` | 17 | 1106 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 17 | 1106 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 17 | 1106 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 17 | 1106 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 17 | 1107 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 17 | 1106 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 17 | 1107 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 17 | 1107 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 25 | 1108 | 16 | 923 | 4406 | 2086 |
| `sieve` | 17 | 1106 | 16 | 916 | 4403 | 2084 |
| `fib` | 17 | 1106 | 16 | 915 | 4402 | 2083 |
| `collatz` | 17 | 1106 | 16 | 915 | 4402 | 2083 |
| `matmul` | 17 | 1107 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 36 | 1130 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 17 | 1108 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1084_ | _1408_ | _+30 %_ | _10.412_ | _142.836_ | _+1272 %_ |
| `lcg` | 1106 | 1408 | +27 % | 65.586 | 176.926 | +170 % |
| `packet_classifier` | 1106 | 1408 | +27 % | 78.623 | 190.182 | +142 % |
| `ring_write` | 1106 | 1408 | +27 % | 78.121 | 189.076 | +142 % |
| `histogram_bins` | 1106 | 1408 | +27 % | 81.262 | 194.080 | +139 % |
| `prefix_scan` | 1107 | 1408 | +27 % | 39.397 | 149.215 | +279 % |
| `binary_search` | 1106 | 1408 | +27 % | 89.781 | 197.947 | +120 % |
| `sort_window` | 1107 | 1409 | +27 % | 69.813 | 179.536 | +157 % |
| `bloom_filter` | 1107 | 1409 | +27 % | 51.402 | 156.952 | +205 % |
| `hash_join` | 1108 | 1411 | +27 % | 67.511 | 183.273 | +171 % |
| `sieve` | 1106 | 1408 | +27 % | 60.193 | 166.997 | +177 % |
| `fib` | 1106 | 1408 | +27 % | 71.236 | 183.557 | +158 % |
| `collatz` | 1106 | 1408 | +27 % | 46.318 | 160.644 | +247 % |
| `matmul` | 1107 | 1408 | +27 % | 58.074 | 169.733 | +192 % |
| `json_parse` | 1130 | 1431 | +27 % | 49.248 | 166.669 | +238 % |
| `nbody` | 1108 | 1410 | +27 % | 78.466 | 193.475 | +147 % |

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
| _(floor: empty program)_ | _2.658_ | _92.329_ | _71.433_ | _56.991_ | _40.505_ | _62.135_ | _73.144_ |
| `lcg` | 2.874 | 108.352 | 59.502 | 65.075 | 40.209 | 69.583 | 80.441 |
| `packet_classifier` | 2.851 | 109.989 | 60.161 | 66.287 | 40.855 | 69.726 | 81.078 |
| `ring_write` | 2.994 | 110.319 | 59.428 | 66.989 | 40.752 | 70.025 | 81.971 |
| `histogram_bins` | 3.049 | 113.461 | 61.265 | 69.633 | 41.280 | 86.506 | 83.631 |
| `prefix_scan` | 3.072 | 115.110 | 60.251 | 71.863 | 42.264 | 74.549 | 84.449 |
| `binary_search` | 3.234 | 113.203 | 60.367 | 68.523 | 40.925 | 74.885 | 87.362 |
| `sort_window` | 3.279 | 120.008 | 61.325 | 73.415 | 41.128 | 80.340 | 91.676 |
| `bloom_filter` | 3.488 | 119.424 | 62.638 | 75.215 | 41.299 | 75.738 | 89.218 |
| `hash_join` | 5.918 | 237.349 | 70.439 | 118.189 | 40.888 | 118.882 | 123.179 |
| `sieve` | 3.139 | 116.307 | 62.537 | 79.150 | 42.812 | 80.651 | 90.485 |
| `fib` | 2.909 | 109.831 | 60.840 | 66.216 | 42.784 | 68.213 | 81.220 |
| `collatz` | 2.997 | 115.650 | 61.164 | 69.025 | 44.525 | 74.061 | 83.641 |
| `matmul` | 3.385 | 124.840 | 62.781 | 82.177 | 41.833 | 96.138 | 103.144 |
| `json_parse` | 53.477 | 624.959 | 153.263 | 123.907 | 42.953 | 184.569 | 162.844 |
| `nbody` | 4.746 | 134.303 | 70.490 | 97.368 | 42.896 | 95.775 | 106.893 |

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
