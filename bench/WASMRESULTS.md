# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-13T04:54:51Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `5df7ff51d29c5382b1d22c0102b40249ea957985` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38348308672 |
| NURL | `v0.72.0-11-g5df7ff51` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.5), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.4.2 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.473_ | _11.217_ | _7.6_ | _1.565_ | _6.753_ | _4.3_ | _1.674_ | _34.052_ | _20.3_ |
| `lcg` | 39.269 | 67.585 | 1.7 | 39.330 | 65.409 | 1.7 | 39.519 | 72.466 | 1.8 |
| `packet_classifier` | 56.406 | 79.834 | 1.4 | 56.637 | 79.028 | 1.4 | 56.739 | 85.370 | 1.5 |
| `ring_write` | 42.395 | 79.501 | 1.9 | 42.489 | 78.994 | 1.9 | 42.699 | 84.530 | 2.0 |
| `histogram_bins` | 39.227 | 77.205 | 2.0 | 41.370 | 75.265 | 1.8 | 39.501 | 83.318 | 2.1 |
| `prefix_scan` | 21.868 | 37.118 | 1.7 | 21.889 | 37.861 | 1.7 | 22.112 | 44.735 | 2.0 |
| `binary_search` | 38.487 | 86.045 | 2.2 | 38.574 | 90.437 | 2.3 | 44.554 | 96.195 | 2.2 |
| `sort_window` | 27.456 | 72.717 | 2.6 | 27.476 | 59.962 | 2.2 | 26.988 | 66.521 | 2.5 |
| `bloom_filter` | 15.463 | 44.354 | 2.9 | 18.298 | 47.121 | 2.6 | 18.488 | 56.087 | 3.0 |
| `hash_join` | 27.951 | 75.198 | 2.7 | 30.310 | 73.394 | 2.4 | 29.992 | 89.163 | 3.0 |
| `sieve` | 20.988 | 57.017 | 2.7 | 18.767 | 58.443 | 3.1 | 20.862 | 55.892 | 2.7 |
| `fib` | 25.186 | 69.845 | 2.8 | 30.044 | 71.983 | 2.4 | 30.026 | 74.058 | 2.5 |
| `collatz` | 12.270 | 45.908 | 3.7 | 12.301 | 45.898 | 3.7 | 12.484 | 52.220 | 4.2 |
| `matmul` | 33.575 | 56.615 | 1.7 | 33.536 | 52.131 | 1.6 | 33.799 | 60.814 | 1.8 |
| `json_parse` | 9.218 | 59.038 | 6.4 | 8.624 | 41.299 | 4.8 | 11.672 | 65.196 | 5.6 |
| `nbody` | 40.921 | 73.200 | 1.8 | 40.714 | 67.213 | 1.7 | 39.100 | 79.506 | 2.0 |
| `chacha20` | 7.617 | 86.503 | 11.4 | 42.171 | 77.011 | 1.8 | 43.797 | 81.703 | 1.9 |
| `poly1305` | 23.505 | 160.426 | 6.8 | 21.205 | 149.677 | 7.1 | 21.270 | 173.864 | 8.2 |
| `blake2b` | 43.929 | 88.290 | 2.0 | 65.882 | 101.526 | 1.5 | 69.125 | 126.142 | 1.8 |
| `sha512` | 46.502 | 97.240 | 2.1 | 50.425 | 91.362 | 1.8 | 49.521 | 96.064 | 1.9 |
| `x25519` | 55.435 | 399.566 | 7.2 | 55.633 | 463.812 | 8.3 | 52.809 | 519.166 | 9.8 |

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
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.7 | — | 1.8 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.5 | — |
| `binary_search` | 2.0 | — | 2.3 | 1.4 |
| `sort_window` | 2.4 | — | 2.1 | — |
| `bloom_filter` | 2.4 | — | 2.4 | — |
| `hash_join` | 2.4 | — | 2.3 | 1.9 |
| `sieve` | 2.3 | — | 3.0 | — |
| `fib` | 2.5 | — | 2.3 | 1.4 |
| `collatz` | 3.2 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 6.2 | — | 4.9 | — |
| `nbody` | 1.6 | — | 1.5 | 1.2 |
| `chacha20` | 12.3 | — | 1.7 | 1.1 |
| `poly1305` | 6.8 | — | 7.3 | 7.1 |
| `blake2b` | 1.8 | — | 1.5 | 1.4 |
| `sha512` | 1.9 | — | 1.7 | 1.3 |
| `x25519` | 7.2 | 6.8 | 8.5 | 9.5 |

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
| _(floor: empty program)_ | _11.217_ | _3.886_ | _6.753_ | _**3.116**_ | _34.052_ | _4.643_ |
| `lcg` | 67.585 | **42.651** | 65.409 | 46.508 | 72.466 | 46.766 |
| `packet_classifier` | 79.834 | **51.960** | 79.028 | 56.188 | 85.370 | 56.368 |
| `ring_write` | 79.501 | **49.158** | 78.994 | 53.354 | 84.530 | 52.915 |
| `histogram_bins` | 77.205 | **44.552** | 75.265 | 50.005 | 83.318 | 52.512 |
| `prefix_scan` | 37.118 | **12.394** | 37.861 | 18.878 | 44.735 | 16.278 |
| `binary_search` | 86.045 | **54.164** | 90.437 | 63.216 | 96.195 | 62.120 |
| `sort_window` | 72.717 | 51.635 | 59.962 | 52.516 | 66.521 | **50.254** |
| `bloom_filter` | 44.354 | 23.402 | 47.121 | 32.186 | 56.087 | **22.301** |
| `hash_join` | 75.198 | **45.024** | 73.394 | 48.626 | 89.163 | 49.020 |
| `sieve` | 57.017 | **32.023** | 58.443 | 38.320 | 55.892 | 32.529 |
| `fib` | 69.845 | 41.856 | 71.983 | 41.833 | 74.058 | **38.435** |
| `collatz` | 45.908 | **24.399** | 45.898 | 26.930 | 52.220 | 26.003 |
| `matmul` | 56.615 | **31.975** | 52.131 | 35.039 | 60.814 | 33.872 |
| `json_parse` | 59.038 | 37.353 | 41.299 | **21.684** | 65.196 | 31.242 |
| `nbody` | 73.200 | 49.748 | 67.213 | **48.953** | 79.506 | 54.137 |
| `chacha20` | 86.503 | **53.937** | 77.011 | 59.865 | 81.703 | 61.621 |
| `poly1305` | 160.426 | 80.133 | 149.677 | 65.200 | 173.864 | **64.964** |
| `blake2b` | 88.290 | **70.202** | 101.526 | 91.324 | 126.142 | 117.772 |
| `sha512` | 97.240 | 75.706 | 91.362 | **71.786** | 96.064 | 72.063 |
| `x25519` | 399.566 | **164.915** | 463.812 | 184.996 | 519.166 | 194.573 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.886_ | _0.3_ | _2.6_ | _0.5_ | _0.1_ |
| `lcg` | 42.651 | 0.6 | 1.1 | 0.7 | 0.6 |
| `packet_classifier` | 51.960 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 49.158 | 0.6 | 1.2 | 0.7 | 0.6 |
| `histogram_bins` | 44.552 | 0.6 | 1.1 | 0.7 | 0.6 |
| `prefix_scan` | 12.394 | 0.3 | 0.6 | 0.5 | 0.4 |
| `binary_search` | 54.164 | 0.6 | 1.4 | 0.7 | 0.6 |
| `sort_window` | 51.635 | 0.7 | 1.9 | 0.9 | 0.8 |
| `bloom_filter` | 23.402 | 0.5 | 1.5 | 0.7 | 0.4 |
| `hash_join` | 45.024 | 0.6 | 1.6 | 0.7 | 0.5 |
| `sieve` | 32.023 | 0.6 | 1.5 | 0.7 | 0.6 |
| `fib` | 41.856 | 0.6 | 1.7 | 0.6 | 0.5 |
| `collatz` | 24.399 | 0.5 | 2.0 | 0.6 | 0.5 |
| `matmul` | 31.975 | 0.6 | 1.0 | 0.7 | 0.6 |
| `json_parse` | 37.353 | 0.6 | 4.1 | 0.5 | 0.5 |
| `nbody` | 49.748 | 0.7 | 1.2 | 0.7 | 0.7 |
| `chacha20` | 53.937 | 0.6 | 7.1 | 0.8 | 0.8 |
| `poly1305` | 80.133 | 0.5 | 3.4 | 0.4 | 0.4 |
| `blake2b` | 70.202 | 0.8 | 1.6 | 0.9 | 0.9 |
| `sha512` | 75.706 | 0.8 | 1.6 | 0.8 | 0.8 |
| `x25519` | 164.915 | 0.4 | 3.0 | 0.4 | 0.4 |

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
| `json_parse` | 49 | 53 | 16 | 1007 | 4445 | 2159 |
| `nbody` | 17 | 28 | 16 | 919 | 4432 | 2130 |
| `chacha20` | 48 | 48 | 16 | 923 | 4432 | 2129 |
| `poly1305` | 28 | 35 | 16 | 921 | 4432 | 2129 |
| `blake2b` | 36 | 42 | 16 | 925 | 4434 | 2132 |
| `sha512` | 36 | 40 | 16 | 922 | 4433 | 2130 |
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
| _(floor: empty program)_ | _4_ | _312_ | _+7748 %_ | _11.217_ | _148.455_ | _+1223 %_ |
| `lcg` | 26 | 313 | +1092 % | 67.585 | 187.965 | +178 % |
| `packet_classifier` | 26 | 312 | +1095 % | 79.834 | 199.722 | +150 % |
| `ring_write` | 26 | 313 | +1092 % | 79.501 | 199.660 | +151 % |
| `histogram_bins` | 26 | 313 | +1090 % | 77.205 | 197.682 | +156 % |
| `prefix_scan` | 27 | 313 | +1076 % | 37.118 | 158.878 | +328 % |
| `binary_search` | 26 | 313 | +1087 % | 86.045 | 207.844 | +142 % |
| `sort_window` | 27 | 313 | +1078 % | 72.717 | 194.775 | +168 % |
| `bloom_filter` | 26 | 313 | +1083 % | 44.354 | 164.295 | +270 % |
| `hash_join` | 28 | 315 | +1014 % | 75.198 | 199.557 | +165 % |
| `sieve` | 26 | 313 | +1092 % | 57.017 | 187.201 | +228 % |
| `fib` | 26 | 312 | +1095 % | 69.845 | 189.243 | +171 % |
| `collatz` | 26 | 312 | +1096 % | 45.908 | 166.793 | +263 % |
| `matmul` | 26 | 313 | +1081 % | 56.615 | 177.215 | +213 % |
| `json_parse` | 53 | 333 | +534 % | 59.038 | 173.948 | +195 % |
| `nbody` | 28 | 314 | +1020 % | 73.200 | 195.453 | +167 % |
| `chacha20` | 48 | 360 | +647 % | 86.503 | 214.186 | +148 % |
| `poly1305` | 35 | 317 | +814 % | 160.426 | 282.735 | +76 % |
| `blake2b` | 42 | 325 | +680 % | 88.290 | 203.322 | +130 % |
| `sha512` | 40 | 323 | +710 % | 97.240 | 211.368 | +117 % |
| `x25519` | 43 | 327 | +657 % | 399.566 | 514.346 | +29 % |

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
| _(floor: empty program)_ | _4.218_ | _105.861_ | _53.044_ | _61.609_ | _42.325_ | _62.965_ | _76.212_ |
| `lcg` | 4.462 | 125.051 | 52.182 | 69.089 | 43.278 | 69.467 | 83.903 |
| `packet_classifier` | 4.350 | 123.573 | 53.447 | 69.527 | 42.664 | 71.880 | 84.446 |
| `ring_write` | 13.120 | 137.807 | 66.855 | 71.838 | 43.157 | 72.451 | 84.745 |
| `histogram_bins` | 13.059 | 139.518 | 69.883 | 73.393 | 43.180 | 74.343 | 86.514 |
| `prefix_scan` | 13.275 | 142.204 | 66.680 | 75.027 | 43.157 | 75.738 | 87.812 |
| `binary_search` | 13.464 | 140.613 | 66.210 | 72.340 | 43.094 | 76.642 | 89.234 |
| `sort_window` | 13.368 | 146.246 | 67.380 | 77.917 | 43.376 | 80.241 | 93.931 |
| `bloom_filter` | 13.945 | 145.699 | 68.355 | 79.466 | 42.226 | 77.041 | 88.603 |
| `hash_join` | 17.842 | 273.454 | 82.538 | 126.989 | 43.659 | 113.116 | 127.406 |
| `sieve` | 13.214 | 139.013 | 67.774 | 80.115 | 41.729 | 84.327 | 92.661 |
| `fib` | 4.439 | 122.799 | 54.523 | 68.591 | 42.257 | 72.569 | 82.773 |
| `collatz` | 4.442 | 124.113 | 53.252 | 70.722 | 42.287 | 70.181 | 82.345 |
| `matmul` | 14.573 | 145.903 | 67.473 | 81.674 | 41.826 | 88.050 | 99.575 |
| `json_parse` | 43.097 | 756.197 | 151.297 | 124.821 | 44.272 | 168.426 | 155.121 |
| `nbody` | 15.375 | 153.771 | 77.315 | 96.476 | 41.522 | 93.499 | 106.925 |
| `chacha20` | 45.716 | 749.511 | 174.503 | 113.213 | 42.844 | 111.414 | 122.984 |
| `poly1305` | 30.349 | 352.732 | 97.736 | 114.421 | 43.000 | 122.430 | 129.700 |
| `blake2b` | 32.618 | 517.306 | 106.801 | 114.092 | 42.776 | 125.190 | 131.874 |
| `sha512` | 32.592 | 484.722 | 116.673 | 101.541 | 42.554 | 113.703 | 121.780 |
| `x25519` | 40.115 | 532.176 | 140.689 | 801.116 | 42.959 | 657.474 | 666.158 |

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
