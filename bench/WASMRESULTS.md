# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-08T08:26:23Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `ee1afce8f0fdcd9ee132c00482d9532fd0260690` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37749428972 |
| NURL | `v0.71.0-5-gee1afce8` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.3), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.3.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.131_ | _11.010_ | _9.7_ | _1.178_ | _5.784_ | _4.9_ | _1.263_ | _20.513_ | _16.2_ |
| `lcg` | 29.933 | 46.012 | 1.5 | 29.383 | 46.950 | 1.6 | 29.398 | 49.525 | 1.7 |
| `packet_classifier` | 42.772 | 51.682 | 1.2 | 42.555 | 51.704 | 1.2 | 41.917 | 55.552 | 1.3 |
| `ring_write` | 28.442 | 50.247 | 1.8 | 29.193 | 49.348 | 1.7 | 29.201 | 53.267 | 1.8 |
| `histogram_bins` | 29.350 | 52.467 | 1.8 | 29.478 | 51.021 | 1.7 | 29.491 | 52.891 | 1.8 |
| `prefix_scan` | 16.144 | 23.103 | 1.4 | 16.298 | 24.842 | 1.5 | 16.489 | 25.421 | 1.5 |
| `binary_search` | 14.727 | 65.959 | 4.5 | 14.685 | 66.384 | 4.5 | 17.618 | 65.691 | 3.7 |
| `sort_window` | 20.598 | 40.529 | 2.0 | 24.663 | 39.761 | 1.6 | 20.745 | 41.999 | 2.0 |
| `bloom_filter` | 8.891 | 26.780 | 3.0 | 8.961 | 27.492 | 3.1 | 9.111 | 29.503 | 3.2 |
| `hash_join` | 17.382 | 46.917 | 2.7 | 18.629 | 44.362 | 2.4 | 18.615 | 50.814 | 2.7 |
| `sieve` | 12.332 | 38.017 | 3.1 | 12.009 | 39.636 | 3.3 | 12.223 | 37.449 | 3.1 |
| `fib` | 19.332 | 47.640 | 2.5 | 19.875 | 44.944 | 2.3 | 20.940 | 46.764 | 2.2 |
| `collatz` | 10.229 | 32.027 | 3.1 | 11.919 | 32.788 | 2.8 | 9.538 | 35.682 | 3.7 |
| `matmul` | 20.837 | 36.953 | 1.8 | 21.054 | 36.372 | 1.7 | 20.875 | 40.773 | 2.0 |
| `json_parse` | 5.485 | 36.049 | 6.6 | 5.435 | 25.054 | 4.6 | 7.126 | 34.455 | 4.8 |
| `nbody` | 24.839 | 43.160 | 1.7 | 24.692 | 43.659 | 1.8 | 23.159 | 46.092 | 2.0 |
| `chacha20` | 23.816 | 60.681 | 2.5 | 20.807 | 50.222 | 2.4 | 21.491 | 50.758 | 2.4 |
| `poly1305` | 26.545 | 155.546 | 5.9 | 26.515 | 150.382 | 5.7 | 31.446 | 195.989 | 6.2 |
| `blake2b` | 138.455 | 348.019 | 2.5 | 43.324 | 69.044 | 1.6 | 48.546 | 77.710 | 1.6 |
| `sha512` | 34.882 | 64.021 | 1.8 | 33.905 | 57.249 | 1.7 | 32.210 | 59.012 | 1.8 |
| `x25519` | 36.137 | 207.164 | 5.7 | 34.492 | 221.116 | 6.4 | 33.010 | 283.822 | 8.6 |

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
| `lcg` | 1.2 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.0 | — | 1.1 | 0.9 |
| `ring_write` | 1.4 | — | 1.6 | 1.2 |
| `histogram_bins` | 1.5 | — | 1.6 | 1.1 |
| `prefix_scan` | 0.8 | — | 1.3 | — |
| `binary_search` | 4.0 | — | 4.5 | 2.8 |
| `sort_window` | 1.5 | — | 1.4 | 1.1 |
| `bloom_filter` | 2.0 | — | 2.8 | — |
| `hash_join` | 2.2 | — | 2.2 | 1.7 |
| `sieve` | 2.4 | — | 3.1 | — |
| `fib` | 2.0 | — | 2.1 | 1.3 |
| `collatz` | 2.3 | — | 2.5 | — |
| `matmul` | 1.3 | — | 1.5 | — |
| `json_parse` | 5.8 | — | 4.5 | — |
| `nbody` | 1.4 | — | 1.6 | 1.2 |
| `chacha20` | 2.2 | — | 2.3 | 1.5 |
| `poly1305` | 5.7 | 5.5 | 5.7 | 5.8 |
| `blake2b` | 2.5 | 2.4 | 1.5 | 1.2 |
| `sha512` | 1.6 | — | 1.6 | 1.2 |
| `x25519` | 5.6 | 5.3 | 6.5 | 8.3 |

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
| _(floor: empty program)_ | _11.010_ | _2.559_ | _5.784_ | _**2.201**_ | _20.513_ | _2.646_ |
| `lcg` | 46.012 | **32.064** | 46.950 | 34.793 | 49.525 | 34.736 |
| `packet_classifier` | 51.682 | **33.376** | 51.704 | 35.844 | 55.552 | 35.658 |
| `ring_write` | 50.247 | **32.026** | 49.348 | 35.025 | 53.267 | 34.656 |
| `histogram_bins` | 52.467 | **31.795** | 51.021 | 33.452 | 52.891 | 33.619 |
| `prefix_scan` | 23.103 | **7.810** | 24.842 | 12.711 | 25.421 | 10.287 |
| `binary_search` | 65.959 | **37.593** | 66.384 | 42.908 | 65.691 | 42.153 |
| `sort_window` | 40.529 | 24.680 | 39.761 | 25.028 | 41.999 | **24.639** |
| `bloom_filter` | 26.780 | **10.590** | 27.492 | 18.917 | 29.503 | 14.035 |
| `hash_join` | 46.917 | **28.721** | 44.362 | 32.521 | 50.814 | 31.882 |
| `sieve` | 38.017 | **20.387** | 39.636 | 22.700 | 37.449 | 20.513 |
| `fib` | 47.640 | 27.257 | 44.944 | 27.252 | 46.764 | **26.376** |
| `collatz` | 32.027 | **16.775** | 32.788 | 19.938 | 35.682 | 19.599 |
| `matmul` | 36.953 | **24.129** | 36.372 | 25.198 | 40.773 | 25.435 |
| `json_parse` | 36.049 | 19.568 | 25.054 | **14.090** | 34.455 | 17.922 |
| `nbody` | 43.160 | **28.521** | 43.659 | 31.873 | 46.092 | 31.175 |
| `chacha20` | 60.681 | **30.530** | 50.222 | 36.028 | 50.758 | 36.235 |
| `poly1305` | 155.546 | **103.441** | 150.382 | 108.024 | 195.989 | 119.972 |
| `blake2b` | 348.019 | 261.938 | 69.044 | **57.395** | 77.710 | 64.271 |
| `sha512` | 64.021 | 47.620 | 57.249 | 48.421 | 59.012 | **46.027** |
| `x25519` | 207.164 | **157.217** | 221.116 | 163.172 | 283.822 | 175.511 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.559_ | _0.2_ | _2.3_ | _0.4_ | _0.1_ |
| `lcg` | 32.064 | 0.7 | 1.1 | 0.7 | 0.7 |
| `packet_classifier` | 33.376 | 0.6 | 0.8 | 0.7 | 0.6 |
| `ring_write` | 32.026 | 0.6 | 1.1 | 0.7 | 0.7 |
| `histogram_bins` | 31.795 | 0.6 | 1.1 | 0.7 | 0.6 |
| `prefix_scan` | 7.810 | 0.3 | 0.5 | 0.5 | 0.4 |
| `binary_search` | 37.593 | 0.6 | 2.6 | 0.6 | 0.6 |
| `sort_window` | 24.680 | 0.6 | 1.2 | 0.6 | 0.6 |
| `bloom_filter` | 10.590 | 0.4 | 1.2 | 0.7 | 0.5 |
| `hash_join` | 28.721 | 0.6 | 1.7 | 0.7 | 0.6 |
| `sieve` | 20.387 | 0.5 | 1.7 | 0.6 | 0.5 |
| `fib` | 27.257 | 0.6 | 1.4 | 0.6 | 0.6 |
| `collatz` | 16.775 | 0.5 | 1.6 | 0.6 | 0.5 |
| `matmul` | 24.129 | 0.7 | 1.2 | 0.7 | 0.6 |
| `json_parse` | 19.568 | 0.5 | 3.6 | 0.6 | 0.5 |
| `nbody` | 28.521 | 0.7 | 1.1 | 0.7 | 0.7 |
| `chacha20` | 30.530 | 0.5 | 1.3 | 0.7 | 0.7 |
| `poly1305` | 103.441 | 0.7 | 3.9 | 0.7 | 0.6 |
| `blake2b` | 261.938 | 0.8 | 1.9 | 0.8 | 0.8 |
| `sha512` | 47.620 | 0.7 | 1.4 | 0.8 | 0.8 |
| `x25519` | 157.217 | 0.8 | 4.4 | 0.7 | 0.6 |

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
| `chacha20` | 31 | 46 | 16 | 923 | 4432 | 2129 |
| `poly1305` | 27 | 32 | 16 | 922 | 4433 | 2130 |
| `blake2b` | 32 | 38 | 16 | 925 | 4434 | 2132 |
| `sha512` | 31 | 37 | 16 | 922 | 4433 | 2130 |
| `x25519` | 35 | 42 | 48 | 1161 | 4464 | 2183 |

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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _11.010_ | _84.002_ | _+663 %_ |
| `lcg` | 26 | 311 | +1087 % | 46.012 | 112.363 | +144 % |
| `packet_classifier` | 26 | 311 | +1090 % | 51.682 | 115.780 | +124 % |
| `ring_write` | 26 | 311 | +1087 % | 50.247 | 116.354 | +132 % |
| `histogram_bins` | 26 | 311 | +1084 % | 52.467 | 115.584 | +120 % |
| `prefix_scan` | 27 | 311 | +1071 % | 23.103 | 88.395 | +283 % |
| `binary_search` | 26 | 311 | +1082 % | 65.959 | 130.629 | +98 % |
| `sort_window` | 27 | 312 | +1073 % | 40.529 | 107.670 | +166 % |
| `bloom_filter` | 26 | 312 | +1078 % | 26.780 | 91.805 | +243 % |
| `hash_join` | 28 | 314 | +1009 % | 46.917 | 109.562 | +134 % |
| `sieve` | 26 | 311 | +1087 % | 38.017 | 108.018 | +184 % |
| `fib` | 26 | 311 | +1090 % | 47.640 | 108.710 | +128 % |
| `collatz` | 26 | 311 | +1091 % | 32.027 | 98.723 | +208 % |
| `matmul` | 26 | 311 | +1076 % | 36.953 | 104.681 | +183 % |
| `json_parse` | 50 | 331 | +561 % | 36.049 | 100.703 | +179 % |
| `nbody` | 28 | 313 | +1016 % | 43.160 | 110.953 | +157 % |
| `chacha20` | 46 | 331 | +621 % | 60.681 | 125.892 | +107 % |
| `poly1305` | 32 | 315 | +870 % | 155.546 | 224.803 | +45 % |
| `blake2b` | 38 | 322 | +743 % | 348.019 | 410.698 | +18 % |
| `sha512` | 37 | 320 | +768 % | 64.021 | 123.128 | +92 % |
| `x25519` | 42 | 326 | +681 % | 207.164 | 268.398 | +30 % |

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
| _(floor: empty program)_ | _2.918_ | _79.937_ | _41.359_ | _51.911_ | _32.170_ | _43.148_ | _51.491_ |
| `lcg` | 3.001 | 95.685 | 37.829 | 52.993 | 33.046 | 47.252 | 55.930 |
| `packet_classifier` | 3.034 | 93.440 | 37.944 | 54.926 | 34.087 | 49.146 | 57.404 |
| `ring_write` | 3.102 | 91.369 | 36.315 | 52.431 | 30.897 | 47.774 | 55.118 |
| `histogram_bins` | 3.239 | 93.601 | 37.126 | 54.795 | 30.257 | 56.073 | 56.361 |
| `prefix_scan` | 3.307 | 92.626 | 36.874 | 54.349 | 30.615 | 49.464 | 57.597 |
| `binary_search` | 3.372 | 93.352 | 37.369 | 52.985 | 30.733 | 51.329 | 58.943 |
| `sort_window` | 3.466 | 97.065 | 39.245 | 57.145 | 30.635 | 53.572 | 60.807 |
| `bloom_filter` | 3.741 | 96.524 | 37.658 | 57.651 | 30.748 | 51.171 | 59.216 |
| `hash_join` | 5.786 | 158.764 | 45.199 | 82.239 | 30.970 | 73.348 | 82.685 |
| `sieve` | 3.426 | 94.419 | 37.350 | 58.917 | 31.147 | 55.849 | 62.584 |
| `fib` | 3.082 | 88.981 | 36.420 | 52.028 | 32.132 | 46.912 | 54.978 |
| `collatz` | 3.223 | 93.156 | 36.964 | 52.170 | 31.421 | 47.503 | 55.765 |
| `matmul` | 4.082 | 97.598 | 38.777 | 60.150 | 32.190 | 61.930 | 67.616 |
| `json_parse` | 28.546 | 410.746 | 90.052 | 84.745 | 31.323 | 117.225 | 102.636 |
| `nbody` | 4.618 | 104.442 | 41.991 | 68.622 | 29.629 | 62.044 | 66.892 |
| `chacha20` | 22.903 | 287.365 | 89.339 | 94.378 | 33.907 | 78.051 | 84.829 |
| `poly1305` | 14.573 | 210.796 | 60.320 | 86.661 | 33.022 | 87.682 | 92.686 |
| `blake2b` | 22.656 | 264.175 | 73.304 | 82.655 | 31.474 | 86.007 | 94.640 |
| `sha512` | 20.653 | 245.012 | 73.421 | 70.034 | 31.100 | 75.487 | 79.923 |
| `x25519` | 22.305 | 293.065 | 81.197 | 445.537 | 31.764 | 394.198 | 387.013 |

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
