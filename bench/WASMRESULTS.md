# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-10T07:06:09Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `d96ce569a77c130a5be5a2360d4f85390e8a39e0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38032952884 |
| NURL | `v0.71.0-23-gd96ce569` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.5), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.4.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.422_ | _10.525_ | _7.4_ | _1.504_ | _5.993_ | _4.0_ | _1.618_ | _34.459_ | _21.3_ |
| `lcg` | 39.014 | 65.268 | 1.7 | 39.107 | 64.787 | 1.7 | 39.165 | 73.119 | 1.9 |
| `packet_classifier` | 56.058 | 79.177 | 1.4 | 56.170 | 78.403 | 1.4 | 56.286 | 85.002 | 1.5 |
| `ring_write` | 41.992 | 77.713 | 1.9 | 42.158 | 77.537 | 1.8 | 42.258 | 83.879 | 2.0 |
| `histogram_bins` | 39.389 | 76.323 | 1.9 | 41.104 | 74.921 | 1.8 | 39.066 | 81.265 | 2.1 |
| `prefix_scan` | 21.612 | 38.096 | 1.8 | 21.690 | 37.879 | 1.7 | 21.842 | 45.688 | 2.1 |
| `binary_search` | 37.933 | 93.016 | 2.5 | 38.035 | 95.005 | 2.5 | 43.922 | 95.623 | 2.2 |
| `sort_window` | 27.121 | 76.498 | 2.8 | 27.121 | 58.023 | 2.1 | 26.738 | 66.460 | 2.5 |
| `bloom_filter` | 15.312 | 42.546 | 2.8 | 18.034 | 45.263 | 2.5 | 18.311 | 53.811 | 2.9 |
| `hash_join` | 27.677 | 74.217 | 2.7 | 29.877 | 78.525 | 2.6 | 29.619 | 80.916 | 2.7 |
| `sieve` | 19.818 | 59.464 | 3.0 | 19.561 | 58.209 | 3.0 | 19.649 | 56.367 | 2.9 |
| `fib` | 25.047 | 71.612 | 2.9 | 29.670 | 75.698 | 2.6 | 29.953 | 78.463 | 2.6 |
| `collatz` | 12.229 | 44.668 | 3.7 | 12.222 | 44.782 | 3.7 | 12.389 | 50.610 | 4.1 |
| `matmul` | 33.304 | 54.282 | 1.6 | 33.331 | 50.211 | 1.5 | 33.427 | 59.968 | 1.8 |
| `json_parse` | 9.485 | 54.786 | 5.8 | 8.541 | 38.454 | 4.5 | 11.637 | 56.071 | 4.8 |
| `nbody` | 40.606 | 77.281 | 1.9 | 40.683 | 69.250 | 1.7 | 38.894 | 80.008 | 2.1 |
| `chacha20` | 7.602 | 82.919 | 10.9 | 42.246 | 75.172 | 1.8 | 43.499 | 83.939 | 1.9 |
| `poly1305` | 23.429 | 159.564 | 6.8 | 20.995 | 146.814 | 7.0 | 21.121 | 175.595 | 8.3 |
| `blake2b` | 43.766 | 84.128 | 1.9 | 65.776 | 105.933 | 1.6 | 68.921 | 133.876 | 1.9 |
| `sha512` | 46.113 | 97.772 | 2.1 | 50.445 | 87.630 | 1.7 | 49.192 | 95.797 | 1.9 |
| `x25519` | 54.463 | 398.138 | 7.3 | 56.318 | 455.106 | 8.1 | 52.526 | 523.231 | 10.0 |

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
| `lcg` | 1.5 | — | 1.6 | 1.0 |
| `packet_classifier` | 1.3 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.8 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.4 | — | 1.6 | — |
| `binary_search` | 2.3 | — | 2.4 | 1.4 |
| `sort_window` | 2.6 | — | 2.0 | — |
| `bloom_filter` | 2.3 | — | 2.4 | — |
| `hash_join` | 2.4 | — | 2.6 | 1.7 |
| `sieve` | 2.7 | — | 2.9 | — |
| `fib` | 2.6 | — | 2.5 | 1.6 |
| `collatz` | 3.2 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.5 | — | 4.6 | — |
| `nbody` | 1.7 | — | 1.6 | 1.2 |
| `chacha20` | 11.7 | — | 1.7 | 1.2 |
| `poly1305` | 6.8 | — | 7.2 | 7.2 |
| `blake2b` | 1.7 | — | 1.6 | 1.5 |
| `sha512` | 2.0 | — | 1.7 | 1.3 |
| `x25519` | 7.3 | 7.0 | 8.2 | 9.6 |

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
| _(floor: empty program)_ | _10.525_ | _3.108_ | _5.993_ | _**2.966**_ | _34.459_ | _4.105_ |
| `lcg` | 65.268 | **43.098** | 64.787 | 46.394 | 73.119 | 46.286 |
| `packet_classifier` | 79.177 | **51.839** | 78.403 | 55.948 | 85.002 | 55.920 |
| `ring_write` | 77.713 | **49.031** | 77.537 | 52.601 | 83.879 | 52.562 |
| `histogram_bins` | 76.323 | **44.063** | 74.921 | 49.932 | 81.265 | 52.038 |
| `prefix_scan` | 38.096 | **10.835** | 37.879 | 17.640 | 45.688 | 15.586 |
| `binary_search` | 93.016 | **52.633** | 95.005 | 58.017 | 95.623 | 65.127 |
| `sort_window` | 76.498 | **50.301** | 58.023 | 52.001 | 66.460 | 52.247 |
| `bloom_filter` | 42.546 | **17.217** | 45.263 | 29.339 | 53.811 | 21.801 |
| `hash_join` | 74.217 | 50.272 | 78.525 | **47.787** | 80.916 | 48.056 |
| `sieve` | 59.464 | **30.600** | 58.209 | 35.694 | 56.367 | 35.828 |
| `fib` | 71.612 | 41.968 | 75.698 | 41.831 | 78.463 | **38.013** |
| `collatz` | 44.668 | **22.256** | 44.782 | 26.279 | 50.610 | 26.791 |
| `matmul` | 54.282 | 33.221 | 50.211 | 34.755 | 59.968 | **32.971** |
| `json_parse` | 54.786 | 34.325 | 38.454 | **21.882** | 56.071 | 35.413 |
| `nbody` | 77.281 | 48.598 | 69.250 | **48.493** | 80.008 | 54.135 |
| `chacha20` | 82.919 | **48.219** | 75.172 | 59.819 | 83.939 | 60.770 |
| `poly1305` | 159.564 | 79.642 | 146.814 | 65.173 | 175.595 | **64.718** |
| `blake2b` | 84.128 | **69.708** | 105.933 | 91.884 | 133.876 | 111.752 |
| `sha512` | 97.772 | 79.826 | 87.630 | **70.712** | 95.797 | 82.437 |
| `x25519` | 398.138 | **162.084** | 455.106 | 191.802 | 523.231 | 185.899 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.108_ | _0.3_ | _2.2_ | _0.5_ | _0.1_ |
| `lcg` | 43.098 | 0.7 | 1.1 | 0.7 | 0.6 |
| `packet_classifier` | 51.839 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 49.031 | 0.6 | 1.2 | 0.7 | 0.6 |
| `histogram_bins` | 44.063 | 0.6 | 1.1 | 0.7 | 0.6 |
| `prefix_scan` | 10.835 | 0.3 | 0.5 | 0.5 | 0.3 |
| `binary_search` | 52.633 | 0.6 | 1.4 | 0.6 | 0.7 |
| `sort_window` | 50.301 | 0.7 | 1.9 | 0.9 | 0.8 |
| `bloom_filter` | 17.217 | 0.4 | 1.1 | 0.6 | 0.4 |
| `hash_join` | 50.272 | 0.7 | 1.8 | 0.6 | 0.6 |
| `sieve` | 30.600 | 0.5 | 1.5 | 0.6 | 0.6 |
| `fib` | 41.968 | 0.6 | 1.7 | 0.6 | 0.5 |
| `collatz` | 22.256 | 0.5 | 1.8 | 0.6 | 0.5 |
| `matmul` | 33.221 | 0.6 | 1.0 | 0.7 | 0.5 |
| `json_parse` | 34.325 | 0.6 | 3.6 | 0.6 | 0.6 |
| `nbody` | 48.598 | 0.6 | 1.2 | 0.7 | 0.7 |
| `chacha20` | 48.219 | 0.6 | 6.3 | 0.8 | 0.7 |
| `poly1305` | 79.642 | 0.5 | 3.4 | 0.4 | 0.4 |
| `blake2b` | 69.708 | 0.8 | 1.6 | 0.9 | 0.8 |
| `sha512` | 79.826 | 0.8 | 1.7 | 0.8 | 0.9 |
| `x25519` | 162.084 | 0.4 | 3.0 | 0.4 | 0.4 |

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
| `json_parse` | 49 | 52 | 16 | 1007 | 4445 | 2159 |
| `nbody` | 17 | 28 | 16 | 919 | 4432 | 2130 |
| `chacha20` | 48 | 48 | 16 | 923 | 4432 | 2129 |
| `poly1305` | 28 | 35 | 16 | 921 | 4432 | 2129 |
| `blake2b` | 36 | 42 | 16 | 925 | 4434 | 2132 |
| `sha512` | 32 | 40 | 16 | 922 | 4433 | 2130 |
| `x25519` | 44 | 43 | 48 | 1161 | 4464 | 2183 |

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
| _(floor: empty program)_ | _4_ | _312_ | _+7737 %_ | _10.525_ | _145.350_ | _+1281 %_ |
| `lcg` | 26 | 312 | +1090 % | 65.268 | 183.673 | +181 % |
| `packet_classifier` | 26 | 312 | +1093 % | 79.177 | 195.449 | +147 % |
| `ring_write` | 26 | 312 | +1090 % | 77.713 | 196.635 | +153 % |
| `histogram_bins` | 26 | 312 | +1088 % | 76.323 | 197.940 | +159 % |
| `prefix_scan` | 27 | 312 | +1074 % | 38.096 | 155.514 | +308 % |
| `binary_search` | 26 | 312 | +1085 % | 93.016 | 204.637 | +120 % |
| `sort_window` | 27 | 313 | +1076 % | 76.498 | 189.375 | +148 % |
| `bloom_filter` | 26 | 312 | +1081 % | 42.546 | 160.145 | +276 % |
| `hash_join` | 28 | 315 | +1012 % | 74.217 | 185.978 | +151 % |
| `sieve` | 26 | 312 | +1090 % | 59.464 | 175.105 | +194 % |
| `fib` | 26 | 312 | +1094 % | 71.612 | 187.090 | +161 % |
| `collatz` | 26 | 312 | +1094 % | 44.668 | 163.660 | +266 % |
| `matmul` | 26 | 312 | +1079 % | 54.282 | 174.011 | +221 % |
| `json_parse` | 52 | 332 | +534 % | 54.786 | 173.962 | +218 % |
| `nbody` | 28 | 314 | +1019 % | 77.281 | 197.126 | +155 % |
| `chacha20` | 48 | 359 | +646 % | 82.919 | 210.036 | +153 % |
| `poly1305` | 35 | 316 | +813 % | 159.564 | 274.517 | +72 % |
| `blake2b` | 42 | 325 | +679 % | 84.128 | 203.002 | +141 % |
| `sha512` | 40 | 322 | +709 % | 97.772 | 211.045 | +116 % |
| `x25519` | 43 | 326 | +656 % | 398.138 | 518.067 | +30 % |

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
| _(floor: empty program)_ | _3.534_ | _97.283_ | _49.625_ | _56.645_ | _40.275_ | _59.503_ | _72.762_ |
| `lcg` | 3.961 | 116.012 | 49.696 | 65.418 | 40.004 | 66.438 | 80.111 |
| `packet_classifier` | 3.907 | 115.850 | 50.805 | 65.938 | 40.498 | 67.552 | 79.678 |
| `ring_write` | 4.129 | 116.874 | 51.254 | 67.437 | 40.146 | 68.728 | 81.075 |
| `histogram_bins` | 4.215 | 120.037 | 50.837 | 68.627 | 40.994 | 70.224 | 83.034 |
| `prefix_scan` | 4.427 | 122.713 | 52.133 | 71.562 | 40.105 | 71.216 | 83.856 |
| `binary_search` | 4.562 | 120.630 | 51.989 | 68.302 | 40.460 | 73.718 | 85.935 |
| `sort_window` | 4.783 | 127.952 | 58.125 | 74.431 | 40.614 | 78.074 | 90.602 |
| `bloom_filter` | 5.362 | 127.821 | 54.073 | 74.812 | 40.328 | 74.228 | 85.652 |
| `hash_join` | 9.507 | 245.319 | 64.826 | 118.792 | 40.942 | 107.475 | 122.188 |
| `sieve` | 4.685 | 122.627 | 51.903 | 77.337 | 39.732 | 80.628 | 89.410 |
| `fib` | 4.077 | 114.821 | 50.064 | 65.370 | 40.306 | 67.029 | 79.303 |
| `collatz` | 4.278 | 119.090 | 50.274 | 66.621 | 40.208 | 67.316 | 80.150 |
| `matmul` | 6.141 | 127.119 | 54.015 | 78.247 | 39.838 | 87.352 | 97.585 |
| `json_parse` | 51.173 | 722.129 | 155.291 | 121.616 | 41.190 | 167.505 | 151.075 |
| `nbody` | 7.072 | 138.617 | 63.386 | 93.933 | 52.335 | 91.076 | 102.926 |
| `chacha20` | 54.799 | 708.628 | 178.245 | 108.839 | 41.027 | 107.113 | 118.771 |
| `poly1305` | 35.663 | 338.667 | 101.619 | 111.935 | 40.176 | 117.118 | 127.909 |
| `blake2b` | 36.818 | 492.990 | 109.399 | 112.391 | 40.031 | 123.475 | 129.601 |
| `sha512` | 37.805 | 463.314 | 120.512 | 96.266 | 40.054 | 108.616 | 119.082 |
| `x25519` | 46.022 | 510.763 | 172.259 | 777.239 | 41.119 | 642.863 | 652.502 |

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
