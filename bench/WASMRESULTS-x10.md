# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-07T20:37:10Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-x10.json`](results/wasm-x10.json).

**Workload ×10.** Every benchmark below does 10 times its published
work (`BENCH_SCALE` in each source: the iteration count, or the number of
repetitions of the kernel, multiplied before compilation), so process
start-up and module compilation are amortised and the generated code is
what the cells measure. The ×1 report is [`WASMRESULTS.md`](WASMRESULTS.md).

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
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `f649d17ce46562eae929fc676296ce84fd7adeed` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37682662732 |
| NURL | `v0.70.0-37-gf649d17c` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.2), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.3.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Workload scale | ×10 — every benchmark's work multiplied by 10 before compilation |
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
| _(floor: empty program)_ | _1.142_ | _7.505_ | _6.6_ | _1.200_ | _6.168_ | _5.1_ | _1.278_ | _21.094_ | _16.5_ |
| `lcg` | 277.621 | 288.472 | 1.0 | 279.378 | 292.416 | 1.0 | 275.487 | 292.501 | 1.1 |
| `packet_classifier` | 396.881 | 325.039 | 0.8 | 397.995 | 326.267 | 0.8 | 391.187 | 326.836 | 0.8 |
| `ring_write` | 281.179 | 338.214 | 1.2 | 279.228 | 343.465 | 1.2 | 280.362 | 351.140 | 1.3 |
| `histogram_bins` | 280.113 | 346.355 | 1.2 | 279.556 | 344.835 | 1.2 | 279.654 | 349.058 | 1.2 |
| `prefix_scan` | 152.232 | 64.025 | 0.4 | 152.126 | 64.587 | 0.4 | 151.256 | 67.292 | 0.4 |
| `binary_search` | 133.586 | 422.508 | 3.2 | 131.142 | 432.396 | 3.3 | 150.348 | 409.494 | 2.7 |
| `sort_window` | 191.532 | 222.708 | 1.2 | 227.052 | 198.657 | 0.9 | 185.035 | 201.723 | 1.1 |
| `bloom_filter` | 74.279 | 101.912 | 1.4 | 74.633 | 101.053 | 1.4 | 74.675 | 92.593 | 1.2 |
| `hash_join` | 152.557 | 230.791 | 1.5 | 163.138 | 259.110 | 1.6 | 165.737 | 255.654 | 1.5 |
| `sieve` | 97.996 | 132.000 | 1.3 | 101.428 | 140.702 | 1.4 | 100.272 | 144.683 | 1.4 |
| `fib` | 175.118 | 258.157 | 1.5 | 180.295 | 255.570 | 1.4 | 183.633 | 243.628 | 1.3 |
| `collatz` | 95.411 | 173.445 | 1.8 | 97.999 | 169.881 | 1.7 | 96.587 | 173.334 | 1.8 |
| `matmul` | 192.338 | 194.011 | 1.0 | 191.315 | 186.493 | 1.0 | 191.228 | 196.293 | 1.0 |
| `json_parse` | 38.944 | 110.398 | 2.8 | 41.821 | 55.159 | 1.3 | 54.810 | 90.979 | 1.7 |
| `nbody` | 245.801 | 246.656 | 1.0 | 246.827 | 244.686 | 1.0 | 220.521 | 240.543 | 1.1 |

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
| `lcg` | 1.0 | 0.9 | 1.0 | 1.0 |
| `packet_classifier` | 0.8 | 0.8 | 0.8 | 0.8 |
| `ring_write` | 1.2 | 1.1 | 1.2 | 1.2 |
| `histogram_bins` | 1.2 | 1.1 | 1.2 | 1.2 |
| `prefix_scan` | 0.4 | — | 0.4 | 0.3 |
| `binary_search` | 3.1 | 3.0 | 3.3 | 2.6 |
| `sort_window` | 1.1 | 1.1 | 0.9 | 1.0 |
| `bloom_filter` | 1.3 | — | 1.3 | 1.0 |
| `hash_join` | 1.5 | 1.4 | 1.6 | 1.4 |
| `sieve` | 1.3 | 1.1 | 1.3 | 1.2 |
| `fib` | 1.4 | 1.3 | 1.4 | 1.2 |
| `collatz` | 1.8 | 1.6 | 1.7 | 1.6 |
| `matmul` | 1.0 | 0.9 | 0.9 | 0.9 |
| `json_parse` | 2.7 | 2.5 | 1.2 | 1.3 |
| `nbody` | 1.0 | 0.9 | 1.0 | 1.0 |

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

Both runtimes side by side first: whole-process wall clock in
milliseconds, each language's module on the reference runtime and on
`nwasm`. The fastest of the six cells in a row is in **bold**.

| Benchmark | NURL on `wasmtime` | NURL on `nwasm` | C on `wasmtime` | C on `nwasm` | Rust on `wasmtime` | Rust on `nwasm` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _7.505_ | _2.906_ | _6.168_ | _**2.449**_ | _21.094_ | _2.711_ |
| `lcg` | 288.472 | **274.165** | 292.416 | 275.734 | 292.501 | 276.445 |
| `packet_classifier` | 325.039 | 290.187 | 326.267 | **287.843** | 326.836 | 292.470 |
| `ring_write` | 338.214 | **281.931** | 343.465 | 285.587 | 351.140 | 286.745 |
| `histogram_bins` | 346.355 | 285.453 | 344.835 | **283.703** | 349.058 | 286.020 |
| `prefix_scan` | 64.025 | **43.097** | 64.587 | 48.055 | 67.292 | 44.515 |
| `binary_search` | 422.508 | **325.200** | 432.396 | 363.027 | 409.494 | 348.155 |
| `sort_window` | 222.708 | 199.869 | 198.657 | 183.354 | 201.723 | **178.502** |
| `bloom_filter` | 101.912 | **64.978** | 101.053 | 87.757 | 92.593 | 74.929 |
| `hash_join` | **230.791** | 236.955 | 259.110 | 252.401 | 255.654 | 249.291 |
| `sieve` | 132.000 | 114.806 | 140.702 | 125.632 | 144.683 | **113.570** |
| `fib` | 258.157 | 218.053 | 255.570 | 199.184 | 243.628 | **191.106** |
| `collatz` | 173.445 | **157.716** | 169.881 | 160.605 | 173.334 | 164.179 |
| `matmul` | 194.011 | **176.894** | 186.493 | 178.601 | 196.293 | 179.236 |
| `json_parse` | 110.398 | 94.128 | 55.159 | **42.793** | 90.979 | 73.472 |
| `nbody` | 246.656 | **239.619** | 244.686 | 242.150 | 240.543 | 240.446 |

`nwasm` is faster than the reference runtime on 14 of 15 NURL modules,
15 of 15 C modules and 15 of 15 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.906_ | _0.4_ | _2.5_ | _0.4_ | _0.1_ |
| `lcg` | 274.165 | 1.0 | 1.0 | 0.9 | 0.9 |
| `packet_classifier` | 290.187 | 0.9 | 0.7 | 0.9 | 0.9 |
| `ring_write` | 281.931 | 0.8 | 1.0 | 0.8 | 0.8 |
| `histogram_bins` | 285.453 | 0.8 | 1.0 | 0.8 | 0.8 |
| `prefix_scan` | 43.097 | 0.7 | 0.3 | 0.7 | 0.7 |
| `binary_search` | 325.200 | 0.8 | 2.4 | 0.8 | 0.9 |
| `sort_window` | 199.869 | 0.9 | 1.0 | 0.9 | 0.9 |
| `bloom_filter` | 64.978 | 0.6 | 0.9 | 0.9 | 0.8 |
| `hash_join` | 236.955 | 1.0 | 1.6 | 1.0 | 1.0 |
| `sieve` | 114.806 | 0.9 | 1.2 | 0.9 | 0.8 |
| `fib` | 218.053 | 0.8 | 1.2 | 0.8 | 0.8 |
| `collatz` | 157.716 | 0.9 | 1.7 | 0.9 | 0.9 |
| `matmul` | 176.894 | 0.9 | 0.9 | 1.0 | 0.9 |
| `json_parse` | 94.128 | 0.9 | 2.4 | 0.8 | 0.8 |
| `nbody` | 239.619 | 1.0 | 1.0 | 1.0 | 1.0 |

The C and Rust columns are the control. They are modules this runtime
never saw during development, emitted by two other LLVM frontends; that
they run at all is a correctness result, and that they run at a similar
ratio says the interpreter has no NURL-shaped fast path.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

Read the wasm columns knowing what each toolchain ships by DEFAULT,
because that is what this table measures and the defaults differ.
Since wasmbuilder 0.3.0 the NURL column is stripped of debug info, which
is what `nurl.sh` has always done natively — the native columns beside it
carry no DWARF either, in any of the three languages. `zig cc` and
`rustc` keep theirs for wasm, and it dominates them: an unstripped NURL
module was 1,126,353 bytes for the empty program, of which 3,070 were
code. So the NURL wasm column is roughly code, and the C and Rust wasm
columns are roughly debug info. Strip all three and they land within a
factor of a few; that comparison is not run here because a benchmark of
shipped artefacts should report what each toolchain actually ships.
Module-load time is unaffected either way — a runtime skips custom
sections — so nothing in sections 1-3 moves with this.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `packet_classifier` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `ring_write` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `histogram_bins` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4431 | 2129 |
| `binary_search` | 17 | 26 | 16 | 916 | 4432 | 2129 |
| `sort_window` | 17 | 27 | 16 | 917 | 4431 | 2129 |
| `bloom_filter` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `hash_join` | 25 | 28 | 16 | 924 | 4433 | 2131 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `fib` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `collatz` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `matmul` | 17 | 27 | 16 | 917 | 4432 | 2129 |
| `json_parse` | 41 | 50 | 16 | 1007 | 4445 | 2159 |
| `nbody` | 17 | 28 | 16 | 919 | 4432 | 2130 |

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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _7.505_ | _90.748_ | _+1109 %_ |
| `lcg` | 26 | 311 | +1087 % | 288.472 | 346.226 | +20 % |
| `packet_classifier` | 26 | 311 | +1090 % | 325.039 | 388.872 | +20 % |
| `ring_write` | 26 | 311 | +1087 % | 338.214 | 407.156 | +20 % |
| `histogram_bins` | 26 | 311 | +1084 % | 346.355 | 411.205 | +19 % |
| `prefix_scan` | 27 | 311 | +1071 % | 64.025 | 131.670 | +106 % |
| `binary_search` | 26 | 311 | +1082 % | 422.508 | 481.915 | +14 % |
| `sort_window` | 27 | 312 | +1073 % | 222.708 | 294.391 | +32 % |
| `bloom_filter` | 26 | 312 | +1078 % | 101.912 | 158.653 | +56 % |
| `hash_join` | 28 | 314 | +1009 % | 230.791 | 310.249 | +34 % |
| `sieve` | 26 | 311 | +1085 % | 132.000 | 197.631 | +50 % |
| `fib` | 26 | 311 | +1083 % | 258.157 | 313.814 | +22 % |
| `collatz` | 26 | 311 | +1091 % | 173.445 | 240.232 | +39 % |
| `matmul` | 27 | 311 | +1074 % | 194.011 | 263.789 | +36 % |
| `json_parse` | 50 | 331 | +561 % | 110.398 | 184.016 | +67 % |
| `nbody` | 28 | 313 | +1016 % | 246.656 | 319.276 | +29 % |

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
| _(floor: empty program)_ | _3.010_ | _84.313_ | _39.077_ | _49.952_ | _32.439_ | _42.894_ | _50.011_ |
| `lcg` | 3.371 | 99.392 | 37.038 | 54.000 | 35.614 | 47.998 | 53.371 |
| `packet_classifier` | 2.916 | 86.160 | 35.904 | 49.615 | 29.885 | 45.290 | 53.582 |
| `ring_write` | 3.038 | 89.019 | 36.896 | 51.602 | 31.672 | 46.759 | 55.410 |
| `histogram_bins` | 6.388 | 101.944 | 34.850 | 53.936 | 31.306 | 48.713 | 55.293 |
| `prefix_scan` | 3.257 | 93.036 | 37.305 | 56.198 | 31.927 | 49.019 | 57.458 |
| `binary_search` | 3.336 | 92.845 | 37.461 | 53.200 | 30.093 | 50.638 | 58.812 |
| `sort_window` | 3.258 | 91.867 | 37.328 | 58.679 | 30.438 | 51.336 | 58.682 |
| `bloom_filter` | 3.654 | 96.697 | 37.576 | 56.101 | 32.742 | 49.886 | 58.112 |
| `hash_join` | 5.417 | 167.965 | 43.157 | 83.581 | 30.245 | 72.945 | 79.933 |
| `sieve` | 3.363 | 96.504 | 37.726 | 59.601 | 29.459 | 57.262 | 59.879 |
| `fib` | 3.022 | 86.735 | 35.004 | 50.301 | 29.868 | 45.093 | 53.438 |
| `collatz` | 2.980 | 87.137 | 34.918 | 53.679 | 31.997 | 46.259 | 56.716 |
| `matmul` | 3.895 | 93.178 | 36.107 | 58.163 | 30.479 | 57.992 | 64.676 |
| `json_parse` | 26.868 | 400.781 | 93.423 | 85.583 | 31.300 | 116.759 | 99.966 |
| `nbody` | 4.773 | 111.881 | 46.752 | 72.979 | 33.310 | 65.070 | 72.530 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-5686402545359347083` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `3079799295` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `7275473283115887719` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `277805545` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `1425077525` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `697754069` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `5836882087` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `23524607` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `0` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `6645790` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `92274650` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `524` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `3932099` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `200` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595259882203992578` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
