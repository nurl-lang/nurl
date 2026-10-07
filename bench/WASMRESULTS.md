# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-07T14:02:19Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `9a6f570dfab380c1dfe912ab815e9896a0add0ba` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37632936648 |
| NURL | `v0.70.0-29-g9a6f570d` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.2), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.1.0 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.196_ | _8.322_ | _7.0_ | _1.253_ | _4.973_ | _4.0_ | _1.372_ | _19.880_ | _14.5_ |
| `lcg` | 29.168 | 46.010 | 1.6 | 28.111 | 48.354 | 1.7 | 29.698 | 48.914 | 1.6 |
| `packet_classifier` | 41.984 | 51.713 | 1.2 | 42.145 | 51.274 | 1.2 | 42.328 | 53.284 | 1.3 |
| `ring_write` | 29.339 | 51.237 | 1.7 | 29.379 | 52.812 | 1.8 | 29.411 | 53.532 | 1.8 |
| `histogram_bins` | 28.973 | 49.356 | 1.7 | 28.146 | 49.452 | 1.8 | 28.374 | 53.869 | 1.9 |
| `prefix_scan` | 16.324 | 21.845 | 1.3 | 16.131 | 23.661 | 1.5 | 16.238 | 26.566 | 1.6 |
| `binary_search` | 13.960 | 58.129 | 4.2 | 14.044 | 64.208 | 4.6 | 16.693 | 62.209 | 3.7 |
| `sort_window` | 20.473 | 39.136 | 1.9 | 24.340 | 38.351 | 1.6 | 20.155 | 41.901 | 2.1 |
| `bloom_filter` | 8.848 | 26.431 | 3.0 | 8.942 | 31.225 | 3.5 | 8.982 | 28.559 | 3.2 |
| `hash_join` | 17.236 | 42.907 | 2.5 | 18.558 | 45.775 | 2.5 | 18.485 | 47.392 | 2.6 |
| `sieve` | 11.862 | 41.393 | 3.5 | 11.805 | 40.960 | 3.5 | 11.851 | 35.583 | 3.0 |
| `fib` | 19.316 | 46.518 | 2.4 | 19.157 | 47.677 | 2.5 | 19.396 | 45.695 | 2.4 |
| `collatz` | 9.570 | 31.261 | 3.3 | 9.880 | 31.913 | 3.2 | 9.444 | 35.124 | 3.7 |
| `matmul` | 20.399 | 36.728 | 1.8 | 20.712 | 34.865 | 1.7 | 20.906 | 42.113 | 2.0 |
| `json_parse` | 5.502 | 37.088 | 6.7 | 5.479 | 25.688 | 4.7 | 7.047 | 34.788 | 4.9 |
| `nbody` | 24.214 | 42.174 | 1.7 | 24.270 | 42.945 | 1.8 | 22.873 | 46.091 | 2.0 |

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
| `lcg` | 1.3 | — | 1.6 | 1.0 |
| `packet_classifier` | 1.1 | — | 1.1 | 0.8 |
| `ring_write` | 1.5 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.5 | — | 1.7 | 1.3 |
| `prefix_scan` | 0.9 | — | 1.3 | — |
| `binary_search` | 3.9 | — | 4.6 | 2.8 |
| `sort_window` | 1.6 | — | 1.4 | 1.2 |
| `bloom_filter` | 2.4 | — | 3.4 | — |
| `hash_join` | 2.2 | — | 2.4 | 1.6 |
| `sieve` | 3.1 | — | 3.4 | — |
| `fib` | 2.1 | — | 2.4 | 1.4 |
| `collatz` | 2.7 | — | 3.1 | — |
| `matmul` | 1.5 | — | 1.5 | 1.1 |
| `json_parse` | 6.7 | — | 4.9 | — |
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

Both runtimes side by side first: whole-process wall clock in
milliseconds, each language's module on the reference runtime and on
`nwasm`. The fastest of the six cells in a row is in **bold**.

| Benchmark | NURL on `wasmtime` | NURL on `nwasm` | C on `wasmtime` | C on `nwasm` | Rust on `wasmtime` | Rust on `nwasm` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _8.322_ | _2.331_ | _4.973_ | _**2.045**_ | _19.880_ | _2.471_ |
| `lcg` | 46.010 | **31.309** | 48.354 | 33.181 | 48.914 | 33.201 |
| `packet_classifier` | 51.713 | **37.061** | 51.274 | 37.733 | 53.284 | 37.637 |
| `ring_write` | 51.237 | **31.579** | 52.812 | 33.362 | 53.532 | 33.374 |
| `histogram_bins` | 49.356 | **30.198** | 49.452 | 32.217 | 53.869 | 32.062 |
| `prefix_scan` | 21.845 | **7.054** | 23.661 | 9.653 | 26.566 | 10.482 |
| `binary_search` | 58.129 | **37.434** | 64.208 | 41.793 | 62.209 | 45.637 |
| `sort_window` | 39.136 | 30.151 | 38.351 | 27.252 | 41.901 | **25.564** |
| `bloom_filter` | 26.431 | **10.207** | 31.225 | 13.030 | 28.559 | 12.540 |
| `hash_join` | 42.907 | 32.481 | 45.775 | **29.944** | 47.392 | 30.314 |
| `sieve` | 41.393 | 20.777 | 40.960 | 21.705 | 35.583 | **20.031** |
| `fib` | 46.518 | 33.297 | 47.677 | **26.283** | 45.695 | 30.857 |
| `collatz` | 31.261 | **19.424** | 31.913 | 21.398 | 35.124 | 20.832 |
| `matmul` | 36.728 | **21.405** | 34.865 | 23.425 | 42.113 | 23.233 |
| `json_parse` | 37.088 | 16.802 | 25.688 | **11.897** | 34.788 | 15.661 |
| `nbody` | 42.174 | 30.068 | 42.945 | **30.011** | 46.091 | 36.538 |

`nwasm` is faster than the reference runtime on 15 of 15 NURL modules,
15 of 15 C modules and 15 of 15 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.331_ | _0.3_ | _1.9_ | _0.4_ | _0.1_ |
| `lcg` | 31.309 | 0.7 | 1.1 | 0.7 | 0.7 |
| `packet_classifier` | 37.061 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 31.579 | 0.6 | 1.1 | 0.6 | 0.6 |
| `histogram_bins` | 30.198 | 0.6 | 1.0 | 0.7 | 0.6 |
| `prefix_scan` | 7.054 | 0.3 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 37.434 | 0.6 | 2.7 | 0.7 | 0.7 |
| `sort_window` | 30.151 | 0.8 | 1.5 | 0.7 | 0.6 |
| `bloom_filter` | 10.207 | 0.4 | 1.2 | 0.4 | 0.4 |
| `hash_join` | 32.481 | 0.8 | 1.9 | 0.7 | 0.6 |
| `sieve` | 20.777 | 0.5 | 1.8 | 0.5 | 0.6 |
| `fib` | 33.297 | 0.7 | 1.7 | 0.6 | 0.7 |
| `collatz` | 19.424 | 0.6 | 2.0 | 0.7 | 0.6 |
| `matmul` | 21.405 | 0.6 | 1.0 | 0.7 | 0.6 |
| `json_parse` | 16.802 | 0.5 | 3.1 | 0.5 | 0.5 |
| `nbody` | 30.068 | 0.7 | 1.2 | 0.7 | 0.8 |

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
| `hash_join` | 25 | 28 | 16 | 923 | 4433 | 2131 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `fib` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `collatz` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `matmul` | 17 | 26 | 16 | 917 | 4431 | 2129 |
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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _8.322_ | _85.526_ | _+928 %_ |
| `lcg` | 26 | 311 | +1087 % | 46.010 | 113.358 | +146 % |
| `packet_classifier` | 26 | 311 | +1090 % | 51.713 | 114.522 | +121 % |
| `ring_write` | 26 | 311 | +1087 % | 51.237 | 118.052 | +130 % |
| `histogram_bins` | 26 | 311 | +1084 % | 49.356 | 113.930 | +131 % |
| `prefix_scan` | 27 | 311 | +1071 % | 21.845 | 89.433 | +309 % |
| `binary_search` | 26 | 311 | +1082 % | 58.129 | 128.068 | +120 % |
| `sort_window` | 27 | 312 | +1073 % | 39.136 | 108.430 | +177 % |
| `bloom_filter` | 26 | 312 | +1078 % | 26.431 | 92.362 | +249 % |
| `hash_join` | 28 | 314 | +1009 % | 42.907 | 112.121 | +161 % |
| `sieve` | 26 | 311 | +1087 % | 41.393 | 104.656 | +153 % |
| `fib` | 26 | 311 | +1090 % | 46.518 | 111.943 | +141 % |
| `collatz` | 26 | 311 | +1091 % | 31.261 | 96.687 | +209 % |
| `matmul` | 26 | 311 | +1076 % | 36.728 | 102.029 | +178 % |
| `json_parse` | 50 | 331 | +561 % | 37.088 | 97.146 | +162 % |
| `nbody` | 28 | 313 | +1016 % | 42.174 | 113.357 | +169 % |

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
| _(floor: empty program)_ | _2.690_ | _73.833_ | _37.047_ | _43.143_ | _28.924_ | _47.329_ | _67.533_ |
| `lcg` | 2.863 | 87.058 | 35.012 | 50.178 | 29.951 | 55.696 | 130.295 |
| `packet_classifier` | 2.910 | 87.157 | 34.623 | 51.277 | 29.502 | 55.194 | 59.931 |
| `ring_write` | 2.961 | 87.705 | 36.512 | 51.485 | 30.171 | 55.462 | 63.466 |
| `histogram_bins` | 3.200 | 92.324 | 36.067 | 52.751 | 29.282 | 57.742 | 63.025 |
| `prefix_scan` | 3.323 | 96.023 | 34.272 | 56.647 | 30.064 | 58.300 | 62.705 |
| `binary_search` | 3.207 | 87.725 | 35.271 | 50.294 | 39.034 | 85.325 | 65.708 |
| `sort_window` | 3.405 | 95.620 | 45.245 | 59.164 | 31.950 | 62.357 | 77.649 |
| `bloom_filter` | 3.518 | 94.719 | 37.840 | 55.992 | 33.655 | 60.586 | 65.494 |
| `hash_join` | 5.578 | 156.371 | 43.748 | 79.651 | 30.610 | 84.010 | 90.805 |
| `sieve` | 3.170 | 91.416 | 34.795 | 55.303 | 31.456 | 60.356 | 70.860 |
| `fib` | 2.836 | 86.503 | 35.937 | 50.966 | 30.893 | 55.005 | 61.267 |
| `collatz` | 3.071 | 88.914 | 36.004 | 51.815 | 30.177 | 55.897 | 62.766 |
| `matmul` | 3.461 | 94.336 | 36.850 | 58.754 | 31.634 | 70.134 | 74.649 |
| `json_parse` | 27.552 | 402.036 | 88.542 | 84.252 | 30.330 | 126.804 | 109.787 |
| `nbody` | 4.461 | 100.345 | 42.064 | 68.123 | 29.591 | 69.150 | 78.959 |

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
