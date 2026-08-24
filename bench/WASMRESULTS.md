# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T15:09:55Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `0274ba0f35f84e0a12021ad953022e0297200765` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32742798495 |
| NURL | `v0.50.0-16-g0274ba0f` |
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
| _(floor: empty program)_ | _1.555_ | _11.137_ | _7.2_ | _1.630_ | _7.998_ | _4.9_ | _1.758_ | _34.910_ | _19.9_ |
| `lcg` | 44.028 | 72.290 | 1.6 | 44.149 | 71.180 | 1.6 | 44.231 | 78.771 | 1.8 |
| `packet_classifier` | 63.382 | 87.628 | 1.4 | 63.539 | 86.605 | 1.4 | 63.653 | 93.625 | 1.5 |
| `ring_write` | 47.730 | 87.346 | 1.8 | 47.670 | 98.946 | 2.1 | 47.856 | 107.650 | 2.2 |
| `histogram_bins` | 51.972 | 98.097 | 1.9 | 52.025 | 96.815 | 1.9 | 52.248 | 103.761 | 2.0 |
| `prefix_scan` | 29.117 | 45.782 | 1.6 | 28.596 | 44.879 | 1.6 | 28.726 | 56.814 | 2.0 |
| `binary_search` | 41.333 | 114.982 | 2.8 | 41.720 | 110.224 | 2.6 | 47.741 | 116.784 | 2.4 |
| `sort_window` | 35.755 | 86.779 | 2.4 | 35.735 | 73.573 | 2.1 | 35.204 | 80.945 | 2.3 |
| `bloom_filter` | 22.978 | 56.493 | 2.5 | 23.720 | 55.941 | 2.4 | 24.094 | 64.166 | 2.7 |
| `hash_join` | 33.940 | 80.794 | 2.4 | 35.900 | 89.778 | 2.5 | 36.295 | 103.910 | 2.9 |
| `sieve` | 23.464 | 67.614 | 2.9 | 23.026 | 69.580 | 3.0 | 22.979 | 69.312 | 3.0 |
| `fib` | 32.563 | 90.870 | 2.8 | 38.750 | 84.641 | 2.2 | 32.654 | 93.044 | 2.8 |
| `collatz` | 15.903 | 56.866 | 3.6 | 16.009 | 55.115 | 3.4 | 16.130 | 64.109 | 4.0 |
| `matmul` | 52.489 | 75.485 | 1.4 | 53.537 | 65.410 | 1.2 | 53.693 | 74.746 | 1.4 |
| `json_parse` | 10.023 | 60.784 | 6.1 | 10.385 | 45.160 | 4.3 | 14.000 | 69.094 | 4.9 |
| `nbody` | 53.783 | 93.937 | 1.7 | 53.815 | 85.112 | 1.6 | 51.303 | 94.442 | 1.8 |

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
| `ring_write` | 1.7 | — | 2.0 | 1.6 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.4 |
| `prefix_scan` | 1.3 | — | 1.4 | — |
| `binary_search` | 2.6 | — | 2.5 | 1.8 |
| `sort_window` | 2.2 | — | 1.9 | 1.4 |
| `bloom_filter` | 2.1 | — | 2.2 | — |
| `hash_join` | 2.2 | — | 2.4 | 2.0 |
| `sieve` | 2.6 | — | 2.9 | — |
| `fib` | 2.6 | — | 2.1 | 1.9 |
| `collatz` | 3.2 | — | 3.3 | — |
| `matmul` | 1.3 | — | 1.1 | 0.8 |
| `json_parse` | 5.9 | — | 4.2 | — |
| `nbody` | 1.6 | — | 1.5 | 1.2 |

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
| _(floor: empty program)_ | _2.752_ | _0.2_ | _1.8_ | _2.785_ | _3.058_ |
| `lcg` | 46.237 | 0.6 | 1.1 | 46.362 | 46.867 |
| `packet_classifier` | 76.096 | 0.9 | 1.2 | 76.741 | 76.610 |
| `ring_write` | 75.953 | 0.9 | 1.6 | 76.040 | 74.327 |
| `histogram_bins` | 83.306 | 0.8 | 1.6 | 88.259 | 83.403 |
| `prefix_scan` | 27.280 | 0.6 | 0.9 | 27.669 | 27.857 |
| `binary_search` | 197.567 | 1.7 | 4.8 | 180.635 | 244.002 |
| `sort_window` | 139.509 | 1.6 | 3.9 | 134.599 | 135.723 |
| `bloom_filter` | 58.062 | 1.0 | 2.5 | 71.450 | 59.843 |
| `hash_join` | 120.332 | 1.5 | 3.5 | 136.533 | 131.949 |
| `sieve` | 78.805 | 1.2 | 3.4 | 78.506 | 63.267 |
| `fib` | 148.353 | 1.6 | 4.6 | 142.534 | 127.420 |
| `collatz` | 39.718 | 0.7 | 2.5 | 38.876 | 42.074 |
| `matmul` | 53.163 | 0.7 | 1.0 | 55.642 | 55.684 |
| `json_parse` | 82.699 | 1.4 | 8.3 | 34.247 | 146.986 |
| `nbody` | 302.763 | 3.2 | 5.6 | 817.763 | 894.131 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _11.137_ | _137.042_ | _+1131 %_ |
| `lcg` | 1093 | 1394 | +28 % | 72.290 | 177.810 | +146 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 87.628 | 195.165 | +123 % |
| `ring_write` | 1093 | 1394 | +28 % | 87.346 | 225.442 | +158 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 98.097 | 217.030 | +121 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 45.782 | 166.880 | +265 % |
| `binary_search` | 1093 | 1394 | +28 % | 114.982 | 235.256 | +105 % |
| `sort_window` | 1094 | 1395 | +28 % | 86.779 | 214.669 | +147 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 56.493 | 177.257 | +214 % |
| `hash_join` | 1095 | 1397 | +28 % | 80.794 | 212.063 | +162 % |
| `sieve` | 1093 | 1394 | +28 % | 67.614 | 198.031 | +193 % |
| `fib` | 1093 | 1394 | +28 % | 90.870 | 212.862 | +134 % |
| `collatz` | 1093 | 1394 | +28 % | 56.866 | 177.022 | +211 % |
| `matmul` | 1093 | 1394 | +28 % | 75.485 | 196.308 | +160 % |
| `json_parse` | 1119 | 1417 | +27 % | 60.784 | 191.241 | +215 % |
| `nbody` | 1095 | 1396 | +27 % | 93.937 | 208.371 | +122 % |

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
| _(floor: empty program)_ | _29.231_ | _139.437_ | _64.252_ | _65.518_ | _45.468_ | _65.189_ | _73.581_ |
| `lcg` | 3.146 | 111.268 | 64.997 | 73.441 | 45.965 | 65.817 | 78.792 |
| `packet_classifier` | 3.220 | 110.383 | 63.258 | 75.928 | 45.045 | 64.104 | 77.781 |
| `ring_write` | 3.307 | 109.858 | 63.414 | 75.375 | 44.649 | 66.432 | 79.271 |
| `histogram_bins` | 3.865 | 129.077 | 75.333 | 87.492 | 53.095 | 77.295 | 91.434 |
| `prefix_scan` | 3.927 | 129.616 | 75.842 | 87.434 | 52.977 | 75.992 | 93.809 |
| `binary_search` | 4.110 | 130.706 | 75.732 | 85.391 | 51.686 | 81.009 | 96.003 |
| `sort_window` | 4.182 | 135.730 | 76.835 | 90.410 | 51.964 | 84.732 | 100.250 |
| `bloom_filter` | 4.511 | 137.007 | 76.140 | 93.042 | 53.014 | 80.609 | 95.310 |
| `hash_join` | 7.505 | 266.256 | 85.950 | 139.560 | 52.188 | 120.343 | 135.104 |
| `sieve` | 3.963 | 133.125 | 77.002 | 95.727 | 52.583 | 84.466 | 97.584 |
| `fib` | 3.633 | 120.936 | 72.626 | 80.884 | 51.252 | 71.158 | 86.909 |
| `collatz` | 3.787 | 125.020 | 74.296 | 81.190 | 50.636 | 74.644 | 92.471 |
| `matmul` | 4.247 | 132.908 | 76.250 | 94.621 | 51.255 | 99.354 | 110.325 |
| `json_parse` | 61.376 | 672.565 | 178.741 | 140.941 | 51.959 | 196.433 | 177.334 |
| `nbody` | 5.930 | 148.971 | 86.009 | 113.009 | 50.676 | 101.493 | 116.890 |

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
