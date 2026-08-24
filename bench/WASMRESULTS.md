# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T19:57:21Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16373440 KiB |
| Commit | `19d680588fff84bf78f2c2cb59f336250602ce5a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32770799312 |
| NURL | `v0.50.0-27-g19d68058` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.0 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.562_ | _10.926_ | _7.0_ | _1.629_ | _7.295_ | _4.5_ | _1.772_ | _35.699_ | _20.1_ |
| `lcg` | 44.090 | 73.181 | 1.7 | 44.116 | 70.963 | 1.6 | 44.273 | 77.803 | 1.8 |
| `packet_classifier` | 63.500 | 87.250 | 1.4 | 63.471 | 86.044 | 1.4 | 63.685 | 93.743 | 1.5 |
| `ring_write` | 47.596 | 86.773 | 1.8 | 47.632 | 86.280 | 1.8 | 47.823 | 92.326 | 1.9 |
| `histogram_bins` | 44.602 | 84.742 | 1.9 | 44.687 | 85.010 | 1.9 | 44.729 | 90.740 | 2.0 |
| `prefix_scan` | 24.466 | 41.642 | 1.7 | 24.482 | 38.411 | 1.6 | 24.671 | 45.055 | 1.8 |
| `binary_search` | 35.579 | 95.966 | 2.7 | 35.919 | 97.258 | 2.7 | 40.886 | 101.625 | 2.5 |
| `sort_window` | 30.734 | 75.260 | 2.4 | 30.762 | 66.017 | 2.1 | 30.089 | 70.957 | 2.4 |
| `bloom_filter` | 19.694 | 48.326 | 2.5 | 20.406 | 51.851 | 2.5 | 20.676 | 53.063 | 2.6 |
| `hash_join` | 29.269 | 69.798 | 2.4 | 30.837 | 75.266 | 2.4 | 31.070 | 81.244 | 2.6 |
| `sieve` | 20.560 | 59.846 | 2.9 | 20.303 | 61.749 | 3.0 | 20.435 | 61.574 | 3.0 |
| `fib` | 27.978 | 78.203 | 2.8 | 33.244 | 78.713 | 2.4 | 28.082 | 99.984 | 3.6 |
| `collatz` | 13.717 | 50.654 | 3.7 | 13.739 | 48.595 | 3.5 | 13.950 | 57.823 | 4.1 |
| `matmul` | 46.027 | 68.754 | 1.5 | 45.542 | 56.360 | 1.2 | 45.857 | 64.545 | 1.4 |
| `json_parse` | 8.578 | 52.489 | 6.1 | 8.857 | 41.389 | 4.7 | 12.152 | 63.439 | 5.2 |
| `nbody` | 46.148 | 77.813 | 1.7 | 46.107 | 73.456 | 1.6 | 44.033 | 81.824 | 1.9 |

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
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.4 | — |
| `binary_search` | 2.5 | — | 2.6 | 1.7 |
| `sort_window` | 2.2 | — | 2.0 | — |
| `bloom_filter` | 2.1 | — | 2.4 | — |
| `hash_join` | 2.1 | — | 2.3 | 1.6 |
| `sieve` | 2.6 | — | 2.9 | — |
| `fib` | 2.5 | — | 2.3 | 2.4 |
| `collatz` | 3.3 | — | 3.4 | — |
| `matmul` | 1.3 | — | 1.1 | — |
| `json_parse` | 5.9 | — | 4.7 | — |
| `nbody` | 1.5 | — | 1.5 | 1.1 |

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
| _(floor: empty program)_ | _2.857_ | _0.3_ | _1.8_ | _2.748_ | _3.093_ |
| `lcg` | 46.574 | 0.6 | 1.1 | 46.320 | 46.866 |
| `packet_classifier` | 66.019 | 0.8 | 1.0 | 66.021 | 63.336 |
| `ring_write` | 54.050 | 0.6 | 1.1 | 53.867 | 63.231 |
| `histogram_bins` | 55.652 | 0.7 | 1.2 | 56.640 | 56.508 |
| `prefix_scan` | 16.368 | 0.4 | 0.7 | 16.108 | 16.949 |
| `binary_search` | 104.480 | 1.1 | 2.9 | 95.173 | 140.018 |
| `sort_window` | 73.285 | 1.0 | 2.4 | 75.594 | 76.035 |
| `bloom_filter` | 29.310 | 0.6 | 1.5 | 33.628 | 30.603 |
| `hash_join` | 69.225 | 1.0 | 2.4 | 74.524 | 73.792 |
| `sieve` | 47.485 | 0.8 | 2.3 | 47.130 | 39.195 |
| `fib` | 112.936 | 1.4 | 4.0 | 117.804 | 105.480 |
| `collatz` | 31.145 | 0.6 | 2.3 | 31.125 | 31.494 |
| `matmul` | 32.819 | 0.5 | 0.7 | 35.774 | 35.761 |
| `json_parse` | 54.453 | 1.0 | 6.3 | 26.845 | 112.146 |
| `nbody` | 99.654 | 1.3 | 2.2 | 732.947 | 823.198 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _10.926_ | _139.363_ | _+1176 %_ |
| `lcg` | 1093 | 1394 | +28 % | 73.181 | 176.986 | +142 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 87.250 | 192.539 | +121 % |
| `ring_write` | 1093 | 1394 | +28 % | 86.773 | 192.689 | +122 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 84.742 | 190.966 | +125 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 41.642 | 148.111 | +256 % |
| `binary_search` | 1093 | 1394 | +28 % | 95.966 | 200.584 | +109 % |
| `sort_window` | 1094 | 1395 | +28 % | 75.260 | 191.449 | +154 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 48.326 | 155.856 | +223 % |
| `hash_join` | 1095 | 1397 | +28 % | 69.798 | 173.745 | +149 % |
| `sieve` | 1093 | 1394 | +28 % | 59.846 | 174.309 | +191 % |
| `fib` | 1093 | 1394 | +28 % | 78.203 | 183.887 | +135 % |
| `collatz` | 1093 | 1394 | +28 % | 50.654 | 158.678 | +213 % |
| `matmul` | 1093 | 1394 | +28 % | 68.754 | 170.892 | +149 % |
| `json_parse` | 1119 | 1417 | +27 % | 52.489 | 163.753 | +212 % |
| `nbody` | 1095 | 1396 | +27 % | 77.813 | 184.167 | +137 % |

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
| _(floor: empty program)_ | _2.915_ | _102.319_ | _62.783_ | _64.245_ | _44.809_ | _59.415_ | _72.450_ |
| `lcg` | 3.197 | 109.113 | 63.610 | 73.833 | 43.742 | 64.924 | 78.532 |
| `packet_classifier` | 3.219 | 109.945 | 62.718 | 73.814 | 43.490 | 64.901 | 78.309 |
| `ring_write` | 3.369 | 111.291 | 63.184 | 75.001 | 43.822 | 66.230 | 80.029 |
| `histogram_bins` | 3.402 | 116.961 | 65.488 | 79.203 | 44.502 | 68.583 | 81.001 |
| `prefix_scan` | 3.518 | 117.811 | 67.460 | 79.189 | 45.367 | 69.989 | 83.998 |
| `binary_search` | 3.624 | 115.421 | 64.502 | 76.183 | 46.397 | 71.325 | 85.155 |
| `sort_window` | 3.733 | 126.103 | 66.378 | 84.286 | 45.596 | 75.315 | 90.389 |
| `bloom_filter` | 3.880 | 122.414 | 68.264 | 85.418 | 47.377 | 74.104 | 86.969 |
| `hash_join` | 6.438 | 231.661 | 75.218 | 123.669 | 45.134 | 107.418 | 122.265 |
| `sieve` | 3.530 | 119.988 | 67.236 | 85.329 | 46.475 | 77.092 | 89.235 |
| `fib` | 3.249 | 111.695 | 64.014 | 75.598 | 47.236 | 64.857 | 79.487 |
| `collatz` | 3.338 | 115.965 | 65.206 | 76.177 | 46.719 | 71.761 | 82.527 |
| `matmul` | 3.778 | 122.513 | 66.314 | 88.592 | 47.777 | 90.261 | 102.554 |
| `json_parse` | 52.555 | 586.520 | 155.981 | 133.711 | 46.349 | 174.895 | 156.219 |
| `nbody` | 5.165 | 131.744 | 74.703 | 101.554 | 46.218 | 90.834 | 103.624 |

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
