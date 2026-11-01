# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-01T18:09:56Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `8b035c6f338e73fe57e833690deac07e046b9e3e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41334837345 |
| NURL | `v0.83.0-55-g8b035c6f` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.7), built from this repo |
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
| _(floor: empty program)_ | _2.731_ | _12.501_ | _4.6_ | _2.792_ | _7.154_ | _2.6_ | _2.867_ | _22.092_ | _7.7_ |
| `lcg` | 31.388 | 48.439 | 1.5 | 31.188 | 49.267 | 1.6 | 31.155 | 50.088 | 1.6 |
| `packet_classifier` | 44.016 | 53.663 | 1.2 | 44.572 | 54.688 | 1.2 | 44.360 | 56.544 | 1.3 |
| `ring_write` | 30.999 | 54.381 | 1.8 | 31.823 | 54.668 | 1.7 | 31.027 | 55.781 | 1.8 |
| `histogram_bins` | 30.925 | 52.683 | 1.7 | 30.020 | 53.906 | 1.8 | 29.656 | 54.752 | 1.8 |
| `prefix_scan` | 18.108 | 25.030 | 1.4 | 17.987 | 25.900 | 1.4 | 18.111 | 27.366 | 1.5 |
| `binary_search` | 16.519 | 61.220 | 3.7 | 16.243 | 63.806 | 3.9 | 18.658 | 65.426 | 3.5 |
| `sort_window` | 24.018 | 44.875 | 1.9 | 40.470 | 40.945 | 1.0 | 22.468 | 42.617 | 1.9 |
| `bloom_filter` | 10.759 | 28.226 | 2.6 | 10.532 | 32.638 | 3.1 | 10.573 | 34.576 | 3.3 |
| `hash_join` | 19.412 | 51.445 | 2.7 | 20.602 | 48.175 | 2.3 | 20.385 | 51.157 | 2.5 |
| `sieve` | 18.172 | 40.893 | 2.3 | 18.121 | 41.358 | 2.3 | 18.054 | 45.111 | 2.5 |
| `fib` | 21.118 | 48.544 | 2.3 | 20.944 | 44.813 | 2.1 | 21.166 | 50.390 | 2.4 |
| `collatz` | 11.216 | 34.011 | 3.0 | 11.100 | 34.580 | 3.1 | 11.311 | 37.833 | 3.3 |
| `matmul` | 21.900 | 38.467 | 1.8 | 22.239 | 36.870 | 1.7 | 22.352 | 39.491 | 1.8 |
| `json_parse` | 5.364 | 34.083 | 6.4 | 8.441 | 25.832 | 3.1 | 11.957 | 35.839 | 3.0 |
| `nbody` | 27.518 | 46.289 | 1.7 | 27.015 | 48.671 | 1.8 | 25.695 | 45.843 | 1.8 |
| `chacha20` | 5.051 | 54.102 | 10.7 | 21.615 | 46.186 | 2.1 | 22.364 | 53.908 | 2.4 |
| `poly1305` | 8.232 | 85.688 | 10.4 | 17.465 | 82.879 | 4.7 | 17.371 | 98.427 | 5.7 |
| `blake2b` | 28.597 | 59.948 | 2.1 | 45.670 | 75.805 | 1.7 | 50.459 | 79.693 | 1.6 |
| `sha512` | 31.697 | 60.637 | 1.9 | 34.294 | 58.425 | 1.7 | 33.969 | 63.040 | 1.9 |
| `x25519` | 20.721 | 172.284 | 8.3 | 34.683 | 224.108 | 6.5 | 33.766 | 287.750 | 8.5 |

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
| `lcg` | 1.3 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.0 | — | 1.1 | 0.8 |
| `ring_write` | 1.5 | — | 1.6 | 1.2 |
| `histogram_bins` | 1.4 | — | 1.7 | 1.2 |
| `prefix_scan` | 0.8 | — | 1.2 | — |
| `binary_search` | 3.5 | — | 4.2 | 2.7 |
| `sort_window` | 1.5 | — | 0.9 | — |
| `bloom_filter` | 2.0 | — | 3.3 | — |
| `hash_join` | 2.3 | — | 2.3 | 1.7 |
| `sieve` | 1.8 | — | 2.2 | 1.5 |
| `fib` | 2.0 | — | 2.1 | 1.5 |
| `collatz` | 2.5 | — | 3.3 | — |
| `matmul` | 1.4 | — | 1.5 | — |
| `json_parse` | — | — | 3.3 | — |
| `nbody` | 1.4 | — | 1.7 | 1.0 |
| `chacha20` | — | — | 2.1 | 1.6 |
| `poly1305` | 13.3 | — | 5.2 | 5.3 |
| `blake2b` | 1.8 | — | 1.6 | 1.2 |
| `sha512` | 1.7 | — | 1.6 | 1.3 |
| `x25519` | 8.9 | 8.9 | 6.8 | 8.6 |

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
| _(floor: empty program)_ | _12.501_ | _4.213_ | _7.154_ | _**3.633**_ | _22.092_ | _5.495_ |
| `lcg` | 48.439 | **33.279** | 49.267 | 36.447 | 50.088 | 35.795 |
| `packet_classifier` | 53.663 | **35.478** | 54.688 | 38.123 | 56.544 | 38.513 |
| `ring_write` | 54.381 | **34.175** | 54.668 | 37.230 | 55.781 | 37.557 |
| `histogram_bins` | 52.683 | **34.928** | 53.906 | 36.202 | 54.752 | 35.989 |
| `prefix_scan` | 25.030 | **10.424** | 25.900 | 14.956 | 27.366 | 13.923 |
| `binary_search` | 61.220 | **40.084** | 63.806 | 44.817 | 65.426 | 44.955 |
| `sort_window` | 44.875 | **27.294** | 40.945 | 27.825 | 42.617 | 27.739 |
| `bloom_filter` | 28.226 | **13.008** | 32.638 | 20.669 | 34.576 | 16.471 |
| `hash_join` | 51.445 | **30.745** | 48.175 | 34.563 | 51.157 | 34.275 |
| `sieve` | 40.893 | **26.605** | 41.358 | 29.819 | 45.111 | 27.898 |
| `fib` | 48.544 | 35.227 | 44.813 | **29.050** | 50.390 | 31.134 |
| `collatz` | 34.011 | **19.735** | 34.580 | 21.900 | 37.833 | 21.590 |
| `matmul` | 38.467 | **24.249** | 36.870 | 27.318 | 39.491 | 27.557 |
| `json_parse` | 34.083 | 21.103 | 25.832 | **17.274** | 35.839 | 19.902 |
| `nbody` | 46.289 | **30.370** | 48.671 | 33.001 | 45.843 | 33.914 |
| `chacha20` | 54.102 | **31.407** | 46.186 | 36.703 | 53.908 | 37.162 |
| `poly1305` | 85.688 | 40.368 | 82.879 | 39.956 | 98.427 | **39.202** |
| `blake2b` | 59.948 | **44.472** | 75.805 | 58.036 | 79.693 | 66.000 |
| `sha512` | 60.637 | 51.108 | 58.425 | 50.627 | 63.040 | **48.185** |
| `x25519` | 172.284 | 105.554 | 224.108 | **97.901** | 287.750 | 100.469 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.213_ | _0.3_ | _1.5_ | _0.5_ | _0.2_ |
| `lcg` | 33.279 | 0.7 | 1.1 | 0.7 | 0.7 |
| `packet_classifier` | 35.478 | 0.7 | 0.8 | 0.7 | 0.7 |
| `ring_write` | 34.175 | 0.6 | 1.1 | 0.7 | 0.7 |
| `histogram_bins` | 34.928 | 0.7 | 1.1 | 0.7 | 0.7 |
| `prefix_scan` | 10.424 | 0.4 | 0.6 | 0.6 | 0.5 |
| `binary_search` | 40.084 | 0.7 | 2.4 | 0.7 | 0.7 |
| `sort_window` | 27.294 | 0.6 | 1.1 | 0.7 | 0.7 |
| `bloom_filter` | 13.008 | 0.5 | 1.2 | 0.6 | 0.5 |
| `hash_join` | 30.745 | 0.6 | 1.6 | 0.7 | 0.7 |
| `sieve` | 26.605 | 0.7 | 1.5 | 0.7 | 0.6 |
| `fib` | 35.227 | 0.7 | 1.7 | 0.6 | 0.6 |
| `collatz` | 19.735 | 0.6 | 1.8 | 0.6 | 0.6 |
| `matmul` | 24.249 | 0.6 | 1.1 | 0.7 | 0.7 |
| `json_parse` | 21.103 | 0.6 | 3.9 | 0.7 | 0.6 |
| `nbody` | 30.370 | 0.7 | 1.1 | 0.7 | 0.7 |
| `chacha20` | 31.407 | 0.6 | 6.2 | 0.8 | 0.7 |
| `poly1305` | 40.368 | 0.5 | 4.9 | 0.5 | 0.4 |
| `blake2b` | 44.472 | 0.7 | 1.6 | 0.8 | 0.8 |
| `sha512` | 51.108 | 0.8 | 1.6 | 0.9 | 0.8 |
| `x25519` | 105.554 | 0.6 | 5.1 | 0.4 | 0.3 |

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
| `lcg` | 18 | 26 | 16 | 915 | 4431 | 2124 |
| `packet_classifier` | 18 | 26 | 16 | 915 | 4432 | 2124 |
| `ring_write` | 18 | 26 | 16 | 915 | 4432 | 2124 |
| `histogram_bins` | 18 | 26 | 16 | 916 | 4432 | 2124 |
| `prefix_scan` | 18 | 27 | 16 | 916 | 4432 | 2124 |
| `binary_search` | 18 | 26 | 16 | 916 | 4433 | 2125 |
| `sort_window` | 18 | 27 | 16 | 917 | 4432 | 2125 |
| `bloom_filter` | 18 | 26 | 16 | 917 | 4432 | 2124 |
| `hash_join` | 26 | 28 | 16 | 923 | 4434 | 2127 |
| `sieve` | 18 | 26 | 16 | 916 | 4431 | 2124 |
| `fib` | 18 | 26 | 16 | 915 | 4431 | 2124 |
| `collatz` | 18 | 26 | 16 | 915 | 4431 | 2124 |
| `matmul` | 18 | 26 | 16 | 917 | 4432 | 2125 |
| `json_parse` | 37 | 46 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 18 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 48 | 40 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 32 | 34 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 32 | 42 | 16 | 925 | 4435 | 2127 |
| `sha512` | 32 | 41 | 16 | 922 | 4433 | 2126 |
| `x25519` | 44 | 47 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _320_ | _+7934 %_ | _12.501_ | _93.199_ | _+646 %_ |
| `lcg` | 26 | 320 | +1120 % | 48.439 | 116.545 | +141 % |
| `packet_classifier` | 26 | 320 | +1123 % | 53.663 | 123.299 | +130 % |
| `ring_write` | 26 | 320 | +1120 % | 54.381 | 123.056 | +126 % |
| `histogram_bins` | 26 | 320 | +1118 % | 52.683 | 126.713 | +141 % |
| `prefix_scan` | 27 | 320 | +1104 % | 25.030 | 99.957 | +299 % |
| `binary_search` | 26 | 320 | +1115 % | 61.220 | 129.542 | +112 % |
| `sort_window` | 27 | 321 | +1106 % | 44.875 | 118.428 | +164 % |
| `bloom_filter` | 26 | 320 | +1111 % | 28.226 | 102.017 | +261 % |
| `hash_join` | 28 | 323 | +1040 % | 51.445 | 124.990 | +143 % |
| `sieve` | 26 | 320 | +1120 % | 40.893 | 113.300 | +177 % |
| `fib` | 26 | 320 | +1124 % | 48.544 | 121.751 | +151 % |
| `collatz` | 26 | 320 | +1124 % | 34.011 | 105.297 | +210 % |
| `matmul` | 26 | 320 | +1109 % | 38.467 | 104.762 | +172 % |
| `json_parse` | 46 | 335 | +624 % | 34.083 | 103.831 | +205 % |
| `nbody` | 28 | 322 | +1047 % | 46.289 | 118.545 | +156 % |
| `chacha20` | 40 | 401 | +894 % | 54.102 | 145.975 | +170 % |
| `poly1305` | 34 | 361 | +950 % | 85.688 | 165.662 | +93 % |
| `blake2b` | 42 | 333 | +686 % | 59.948 | 127.151 | +112 % |
| `sha512` | 41 | 331 | +716 % | 60.637 | 133.777 | +121 % |
| `x25519` | 47 | 352 | +642 % | 172.284 | 252.970 | +47 % |

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
| _(floor: empty program)_ | _5.383_ | _94.409_ | _42.269_ | _48.969_ | _34.115_ | _53.170_ | _59.107_ |
| `lcg` | 5.519 | 103.209 | 41.873 | 55.760 | 33.892 | 60.620 | 68.837 |
| `packet_classifier` | 5.713 | 103.775 | 41.387 | 54.016 | 33.694 | 66.311 | 75.182 |
| `ring_write` | 11.372 | 114.029 | 54.159 | 54.727 | 34.671 | 61.934 | 68.745 |
| `histogram_bins` | 11.214 | 115.650 | 49.749 | 57.753 | 34.025 | 65.919 | 69.488 |
| `prefix_scan` | 11.023 | 112.884 | 46.173 | 57.606 | 34.840 | 61.128 | 69.572 |
| `binary_search` | 11.217 | 114.774 | 48.069 | 55.892 | 33.836 | 64.432 | 69.983 |
| `sort_window` | 14.727 | 128.253 | 48.877 | 59.846 | 34.084 | 67.449 | 93.137 |
| `bloom_filter` | 11.727 | 144.062 | 49.814 | 59.789 | 34.062 | 65.756 | 71.530 |
| `hash_join` | 13.682 | 181.073 | 57.321 | 88.366 | 35.137 | 90.041 | 95.730 |
| `sieve` | 11.442 | 117.748 | 51.753 | 63.532 | 36.341 | 72.233 | 78.757 |
| `fib` | 5.804 | 107.936 | 43.342 | 58.488 | 34.925 | 63.066 | 66.128 |
| `collatz` | 5.963 | 108.490 | 42.130 | 57.488 | 34.396 | 64.511 | 68.307 |
| `matmul` | 11.774 | 120.410 | 50.111 | 63.389 | 33.379 | 81.085 | 79.077 |
| `json_parse` | 29.414 | 304.531 | 95.835 | 81.313 | 36.494 | 130.743 | 117.245 |
| `nbody` | 11.993 | 127.735 | 57.457 | 73.563 | 36.646 | 78.655 | 83.369 |
| `chacha20` | 39.031 | 495.490 | 125.659 | 82.808 | 34.143 | 92.689 | 95.053 |
| `poly1305` | 33.117 | 318.859 | 90.580 | 76.151 | 34.968 | 98.025 | 108.914 |
| `blake2b` | 23.428 | 290.026 | 74.360 | 79.819 | 35.327 | 99.502 | 104.941 |
| `sha512` | 23.650 | 280.608 | 75.799 | 76.455 | 34.027 | 93.454 | 98.220 |
| `x25519` | 31.303 | 888.099 | 95.868 | 437.918 | 36.418 | 428.530 | 439.156 |

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
