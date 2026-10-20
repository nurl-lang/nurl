# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-20T05:45:35Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `df213fb80d7791da9e873413c2851a28b7880018` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39376175627 |
| NURL | `v0.74.0-5-gdf213fb8` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.6), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.3 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Workload scale | ×1 — the published contract (`--scale N` multiplies it) |
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
| _(floor: empty program)_ | _1.324_ | _10.177_ | _7.7_ | _1.362_ | _6.626_ | _4.9_ | _1.502_ | _28.314_ | _18.9_ |
| `lcg` | 34.466 | 56.382 | 1.6 | 34.438 | 56.151 | 1.6 | 34.595 | 60.556 | 1.8 |
| `packet_classifier` | 49.477 | 67.952 | 1.4 | 49.504 | 67.863 | 1.4 | 49.644 | 72.273 | 1.5 |
| `ring_write` | 37.210 | 68.125 | 1.8 | 37.183 | 67.921 | 1.8 | 37.336 | 71.438 | 1.9 |
| `histogram_bins` | 34.760 | 65.468 | 1.9 | 34.822 | 65.863 | 1.9 | 34.910 | 68.976 | 2.0 |
| `prefix_scan` | 19.148 | 30.033 | 1.6 | 19.216 | 34.484 | 1.8 | 19.331 | 36.249 | 1.9 |
| `binary_search` | 27.994 | 73.882 | 2.6 | 28.048 | 81.488 | 2.9 | 36.725 | 77.879 | 2.1 |
| `sort_window` | 23.945 | 68.886 | 2.9 | 24.045 | 53.706 | 2.2 | 23.591 | 55.508 | 2.4 |
| `bloom_filter` | 13.534 | 36.024 | 2.7 | 15.916 | 45.247 | 2.8 | 16.179 | 40.258 | 2.5 |
| `hash_join` | 22.820 | 59.366 | 2.6 | 24.080 | 63.349 | 2.6 | 24.239 | 62.118 | 2.6 |
| `sieve` | 20.448 | 47.779 | 2.3 | 18.885 | 58.397 | 3.1 | 18.957 | 48.804 | 2.6 |
| `fib` | 21.887 | 62.149 | 2.8 | 25.951 | 58.557 | 2.3 | 26.105 | 63.849 | 2.4 |
| `collatz` | 10.790 | 38.385 | 3.6 | 10.838 | 38.191 | 3.5 | 10.936 | 42.750 | 3.9 |
| `matmul` | 34.674 | 51.226 | 1.5 | 35.522 | 45.297 | 1.3 | 36.148 | 50.532 | 1.4 |
| `json_parse` | 7.082 | 46.716 | 6.6 | 7.131 | 34.720 | 4.9 | 9.675 | 46.133 | 4.8 |
| `nbody` | 36.038 | 58.453 | 1.6 | 36.073 | 59.208 | 1.6 | 34.395 | 64.930 | 1.9 |
| `chacha20` | 7.120 | 72.587 | 10.2 | 35.953 | 59.453 | 1.7 | 35.562 | 64.610 | 1.8 |
| `poly1305` | 20.719 | 117.201 | 5.7 | 18.664 | 119.751 | 6.4 | 18.828 | 138.692 | 7.4 |
| `blake2b` | 37.986 | 71.418 | 1.9 | 57.497 | 89.277 | 1.6 | 60.885 | 113.338 | 1.9 |
| `sha512` | 38.999 | 75.693 | 1.9 | 41.646 | 72.767 | 1.7 | 42.279 | 76.740 | 1.8 |
| `x25519` | 46.933 | 287.876 | 6.1 | 48.961 | 342.060 | 7.0 | 45.912 | 424.824 | 9.3 |

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
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.1 | — | 1.6 | — |
| `binary_search` | 2.4 | — | 2.8 | 1.4 |
| `sort_window` | 2.6 | — | 2.1 | — |
| `bloom_filter` | 2.1 | — | 2.7 | — |
| `hash_join` | 2.3 | — | 2.5 | 1.5 |
| `sieve` | 2.0 | — | 3.0 | — |
| `fib` | 2.5 | — | 2.1 | 1.4 |
| `collatz` | 3.0 | — | 3.3 | — |
| `matmul` | 1.2 | — | 1.1 | — |
| `json_parse` | 6.3 | — | 4.9 | — |
| `nbody` | 1.4 | — | 1.5 | 1.1 |
| `chacha20` | 10.8 | — | 1.5 | 1.1 |
| `poly1305` | 5.5 | — | 6.5 | 6.4 |
| `blake2b` | 1.7 | — | 1.5 | 1.4 |
| `sha512` | 1.7 | — | 1.6 | 1.2 |
| `x25519` | 6.1 | 6.0 | 7.0 | 8.9 |

## 3. The pure-NURL runtime (`packages/nwasm`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with two JIT tiers
on top — a register-allocating JIT, the default on x86-64, and the template
JIT it falls back to (`NURL_NWASM_RJIT=0` keeps the template tier,
`NURL_NWASM_JIT=0` the pure interpreter; metered or shared-memory runs
fall back to the interpreter on their own).
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
| _(floor: empty program)_ | _10.177_ | _2.815_ | _6.626_ | _**2.423**_ | _28.314_ | _3.976_ |
| `lcg` | 56.382 | **37.689** | 56.151 | 40.360 | 60.556 | 40.715 |
| `packet_classifier` | 67.952 | **45.580** | 67.863 | 48.892 | 72.273 | 48.928 |
| `ring_write` | 68.125 | **42.954** | 67.921 | 45.991 | 71.438 | 46.078 |
| `histogram_bins` | 65.468 | **38.485** | 65.863 | 43.020 | 68.976 | 42.244 |
| `prefix_scan` | 30.033 | **9.703** | 34.484 | 17.357 | 36.249 | 13.660 |
| `binary_search` | 73.882 | **45.313** | 81.488 | 48.380 | 77.879 | 52.247 |
| `sort_window` | 68.886 | 39.723 | 53.706 | 39.440 | 55.508 | **37.973** |
| `bloom_filter` | 36.024 | **15.953** | 45.247 | 18.997 | 40.258 | 19.053 |
| `hash_join` | 59.366 | **35.318** | 63.349 | 38.808 | 62.118 | 49.857 |
| `sieve` | 47.779 | **30.482** | 58.397 | 34.612 | 48.804 | 36.471 |
| `fib` | 62.149 | 34.539 | 58.557 | 34.776 | 63.849 | **31.484** |
| `collatz` | 38.385 | **20.013** | 38.191 | 22.750 | 42.750 | 22.716 |
| `matmul` | 51.226 | 30.469 | 45.297 | **29.958** | 50.532 | 30.332 |
| `json_parse` | 46.716 | 26.119 | 34.720 | **22.414** | 46.133 | 24.333 |
| `nbody` | 58.453 | 51.820 | 59.208 | **42.452** | 64.930 | 44.465 |
| `chacha20` | 72.587 | **40.219** | 59.453 | 47.803 | 64.610 | 48.187 |
| `poly1305` | 117.201 | 66.155 | 119.751 | **54.601** | 138.692 | 56.729 |
| `blake2b` | 71.418 | **54.348** | 89.277 | 77.133 | 113.338 | 91.582 |
| `sha512` | 75.693 | **52.991** | 72.767 | 59.137 | 76.740 | 60.103 |
| `x25519` | 287.876 | **133.634** | 342.060 | 150.884 | 424.824 | 149.768 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.815_ | _0.3_ | _2.1_ | _0.4_ | _0.1_ |
| `lcg` | 37.689 | 0.7 | 1.1 | 0.7 | 0.7 |
| `packet_classifier` | 45.580 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 42.954 | 0.6 | 1.2 | 0.7 | 0.6 |
| `histogram_bins` | 38.485 | 0.6 | 1.1 | 0.7 | 0.6 |
| `prefix_scan` | 9.703 | 0.3 | 0.5 | 0.5 | 0.4 |
| `binary_search` | 45.313 | 0.6 | 1.6 | 0.6 | 0.7 |
| `sort_window` | 39.723 | 0.6 | 1.7 | 0.7 | 0.7 |
| `bloom_filter` | 15.953 | 0.4 | 1.2 | 0.4 | 0.5 |
| `hash_join` | 35.318 | 0.6 | 1.5 | 0.6 | 0.8 |
| `sieve` | 30.482 | 0.6 | 1.5 | 0.6 | 0.7 |
| `fib` | 34.539 | 0.6 | 1.6 | 0.6 | 0.5 |
| `collatz` | 20.013 | 0.5 | 1.9 | 0.6 | 0.5 |
| `matmul` | 30.469 | 0.6 | 0.9 | 0.7 | 0.6 |
| `json_parse` | 26.119 | 0.6 | 3.7 | 0.6 | 0.5 |
| `nbody` | 51.820 | 0.9 | 1.4 | 0.7 | 0.7 |
| `chacha20` | 40.219 | 0.6 | 5.6 | 0.8 | 0.7 |
| `poly1305` | 66.155 | 0.6 | 3.2 | 0.5 | 0.4 |
| `blake2b` | 54.348 | 0.8 | 1.4 | 0.9 | 0.8 |
| `sha512` | 52.991 | 0.7 | 1.4 | 0.8 | 0.8 |
| `x25519` | 133.634 | 0.5 | 2.8 | 0.4 | 0.4 |

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
| `lcg` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `packet_classifier` | 17 | 26 | 16 | 915 | 4432 | 2124 |
| `ring_write` | 17 | 26 | 16 | 915 | 4432 | 2124 |
| `histogram_bins` | 17 | 26 | 16 | 916 | 4432 | 2124 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4432 | 2124 |
| `binary_search` | 17 | 26 | 16 | 916 | 4433 | 2125 |
| `sort_window` | 17 | 27 | 16 | 917 | 4432 | 2125 |
| `bloom_filter` | 17 | 26 | 16 | 917 | 4432 | 2124 |
| `hash_join` | 25 | 28 | 16 | 923 | 4434 | 2127 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2124 |
| `fib` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `collatz` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `matmul` | 17 | 26 | 16 | 917 | 4432 | 2125 |
| `json_parse` | 49 | 53 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 17 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 56 | 48 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 28 | 35 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 36 | 41 | 16 | 925 | 4435 | 2127 |
| `sha512` | 36 | 40 | 16 | 922 | 4433 | 2126 |
| `x25519` | 44 | 43 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _314_ | _+7802 %_ | _10.177_ | _118.065_ | _+1060 %_ |
| `lcg` | 26 | 315 | +1100 % | 56.382 | 147.663 | +162 % |
| `packet_classifier` | 26 | 315 | +1103 % | 67.952 | 159.518 | +135 % |
| `ring_write` | 26 | 315 | +1100 % | 68.125 | 158.276 | +132 % |
| `histogram_bins` | 26 | 315 | +1098 % | 65.468 | 163.789 | +150 % |
| `prefix_scan` | 27 | 315 | +1085 % | 30.033 | 123.397 | +311 % |
| `binary_search` | 26 | 315 | +1095 % | 73.882 | 169.513 | +129 % |
| `sort_window` | 27 | 315 | +1086 % | 68.886 | 147.155 | +114 % |
| `bloom_filter` | 26 | 315 | +1091 % | 36.024 | 131.932 | +266 % |
| `hash_join` | 28 | 318 | +1021 % | 59.366 | 147.550 | +149 % |
| `sieve` | 26 | 315 | +1100 % | 47.779 | 143.229 | +200 % |
| `fib` | 26 | 314 | +1103 % | 62.149 | 149.866 | +141 % |
| `collatz` | 26 | 315 | +1104 % | 38.385 | 128.914 | +236 % |
| `matmul` | 26 | 315 | +1089 % | 51.226 | 142.945 | +179 % |
| `json_parse` | 53 | 335 | +538 % | 46.716 | 136.700 | +193 % |
| `nbody` | 28 | 316 | +1028 % | 58.453 | 154.718 | +165 % |
| `chacha20` | 48 | 362 | +652 % | 72.587 | 171.542 | +136 % |
| `poly1305` | 35 | 319 | +820 % | 117.201 | 204.778 | +75 % |
| `blake2b` | 41 | 327 | +694 % | 71.418 | 167.372 | +134 % |
| `sha512` | 40 | 325 | +715 % | 75.693 | 163.850 | +116 % |
| `x25519` | 43 | 328 | +664 % | 287.876 | 390.097 | +36 % |

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
| _(floor: empty program)_ | _3.836_ | _96.117_ | _46.983_ | _58.368_ | _39.142_ | _59.871_ | _71.792_ |
| `lcg` | 4.125 | 114.393 | 47.860 | 65.649 | 38.672 | 66.653 | 184.255 |
| `packet_classifier` | 4.028 | 113.268 | 48.217 | 66.176 | 38.279 | 66.725 | 78.137 |
| `ring_write` | 11.075 | 121.153 | 59.901 | 66.192 | 42.173 | 67.516 | 151.586 |
| `histogram_bins` | 11.408 | 124.076 | 56.762 | 67.781 | 43.005 | 68.061 | 79.427 |
| `prefix_scan` | 11.345 | 125.796 | 56.822 | 69.732 | 38.301 | 68.549 | 80.594 |
| `binary_search` | 11.542 | 125.350 | 59.813 | 67.469 | 38.670 | 70.005 | 79.785 |
| `sort_window` | 11.367 | 128.667 | 58.269 | 71.260 | 38.528 | 74.844 | 86.327 |
| `bloom_filter` | 11.635 | 127.561 | 58.900 | 70.993 | 39.326 | 71.535 | 80.919 |
| `hash_join` | 14.377 | 214.855 | 69.173 | 102.705 | 38.226 | 97.511 | 109.865 |
| `sieve` | 11.353 | 124.890 | 61.267 | 73.434 | 38.697 | 76.878 | 86.800 |
| `fib` | 4.198 | 111.003 | 51.483 | 65.143 | 37.935 | 67.480 | 78.425 |
| `collatz` | 4.189 | 115.321 | 49.296 | 66.476 | 38.261 | 67.862 | 99.090 |
| `matmul` | 12.399 | 129.480 | 59.935 | 75.391 | 38.784 | 85.291 | 93.607 |
| `json_parse` | 36.590 | 576.770 | 126.802 | 107.086 | 40.098 | 153.698 | 139.202 |
| `nbody` | 13.255 | 139.676 | 69.232 | 86.578 | 39.863 | 90.106 | 96.794 |
| `chacha20` | 38.061 | 634.618 | 142.732 | 95.505 | 39.079 | 103.046 | 112.156 |
| `poly1305` | 25.438 | 289.467 | 99.111 | 100.766 | 39.214 | 110.454 | 119.529 |
| `blake2b` | 29.517 | 422.374 | 95.247 | 101.481 | 39.865 | 118.246 | 121.446 |
| `sha512` | 29.755 | 383.817 | 108.381 | 88.478 | 38.862 | 103.986 | 118.631 |
| `x25519` | 33.060 | 420.197 | 120.772 | 611.379 | 39.113 | 520.089 | 537.580 |

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
| `chacha20` | `3720502699256473595` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `2498856793803813402` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `8590291023788228918` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sha512` | `7091519178481951668` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `x25519` | `6127485567278337128` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
