# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-27T15:49:35Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `7724410934ad521cd949f86273afd94495f07f4f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40533811166 |
| NURL | `v0.79.0-2-g77244109` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
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
| _(floor: empty program)_ | _1.570_ | _12.565_ | _8.0_ | _1.661_ | _6.896_ | _4.2_ | _1.781_ | _33.588_ | _18.9_ |
| `lcg` | 44.100 | 71.341 | 1.6 | 44.107 | 71.463 | 1.6 | 44.269 | 77.542 | 1.8 |
| `packet_classifier` | 63.504 | 86.057 | 1.4 | 63.537 | 85.835 | 1.4 | 63.703 | 90.840 | 1.4 |
| `ring_write` | 47.645 | 84.697 | 1.8 | 47.688 | 85.641 | 1.8 | 47.832 | 91.652 | 1.9 |
| `histogram_bins` | 44.659 | 83.181 | 1.9 | 44.653 | 83.364 | 1.9 | 44.787 | 87.856 | 2.0 |
| `prefix_scan` | 24.429 | 39.049 | 1.6 | 24.528 | 38.546 | 1.6 | 24.658 | 47.240 | 1.9 |
| `binary_search` | 41.720 | 96.266 | 2.3 | 35.776 | 95.099 | 2.7 | 47.111 | 98.593 | 2.1 |
| `sort_window` | 30.739 | 81.337 | 2.6 | 30.725 | 67.768 | 2.2 | 30.136 | 71.612 | 2.4 |
| `bloom_filter` | 17.369 | 45.503 | 2.6 | 20.316 | 49.219 | 2.4 | 20.566 | 50.303 | 2.4 |
| `hash_join` | 29.003 | 81.326 | 2.8 | 30.720 | 75.521 | 2.5 | 31.002 | 83.786 | 2.7 |
| `sieve` | 20.653 | 61.795 | 3.0 | 20.274 | 70.782 | 3.5 | 20.228 | 57.025 | 2.8 |
| `fib` | 33.092 | 72.796 | 2.2 | 33.136 | 73.522 | 2.2 | 33.335 | 87.295 | 2.6 |
| `collatz` | 13.764 | 49.355 | 3.6 | 13.726 | 48.517 | 3.5 | 13.903 | 54.364 | 3.9 |
| `matmul` | 45.428 | 61.036 | 1.3 | 45.751 | 55.728 | 1.2 | 46.681 | 63.601 | 1.4 |
| `json_parse` | 8.475 | 56.448 | 6.7 | 8.896 | 39.856 | 4.5 | 12.027 | 62.069 | 5.2 |
| `nbody` | 46.275 | 80.061 | 1.7 | 46.759 | 74.603 | 1.6 | 44.260 | 81.835 | 1.8 |
| `chacha20` | 8.718 | 93.853 | 10.8 | 46.334 | 75.602 | 1.6 | 45.781 | 83.770 | 1.8 |
| `poly1305` | 12.494 | 151.192 | 12.1 | 23.762 | 148.120 | 6.2 | 23.929 | 176.784 | 7.4 |
| `blake2b` | 48.598 | 102.945 | 2.1 | 73.821 | 117.696 | 1.6 | 78.267 | 143.998 | 1.8 |
| `sha512` | 50.063 | 102.968 | 2.1 | 53.511 | 100.407 | 1.9 | 54.158 | 100.310 | 1.9 |
| `x25519` | 48.569 | 340.827 | 7.0 | 62.916 | 437.279 | 7.0 | 59.402 | 546.945 | 9.2 |

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
| `ring_write` | 1.6 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.6 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.2 | — | 1.4 | — |
| `binary_search` | 2.1 | — | 2.6 | 1.4 |
| `sort_window` | 2.4 | — | 2.1 | 1.3 |
| `bloom_filter` | 2.1 | — | 2.3 | — |
| `hash_join` | 2.5 | — | 2.4 | 1.7 |
| `sieve` | 2.6 | — | 3.4 | — |
| `fib` | 1.9 | — | 2.1 | 1.7 |
| `collatz` | 3.0 | — | 3.4 | — |
| `matmul` | 1.1 | — | 1.1 | — |
| `json_parse` | 6.4 | — | 4.6 | — |
| `nbody` | 1.5 | — | 1.5 | 1.1 |
| `chacha20` | 11.4 | — | 1.5 | 1.1 |
| `poly1305` | 12.7 | — | 6.4 | 6.5 |
| `blake2b` | 1.9 | — | 1.5 | 1.4 |
| `sha512` | 1.9 | — | 1.8 | 1.3 |
| `x25519` | 7.0 | 6.7 | 7.0 | 8.9 |

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
| _(floor: empty program)_ | _12.565_ | _3.346_ | _6.896_ | _**2.982**_ | _33.588_ | _3.582_ |
| `lcg` | 71.341 | **47.429** | 71.463 | 51.570 | 77.542 | 50.897 |
| `packet_classifier` | 86.057 | **58.270** | 85.835 | 62.406 | 90.840 | 62.141 |
| `ring_write` | 84.697 | **54.808** | 85.641 | 58.509 | 91.652 | 58.214 |
| `histogram_bins` | 83.181 | **49.455** | 83.364 | 54.861 | 87.856 | 52.667 |
| `prefix_scan` | 39.049 | **12.466** | 38.546 | 19.520 | 47.240 | 17.828 |
| `binary_search` | 96.266 | **57.461** | 95.099 | 62.088 | 98.593 | 65.915 |
| `sort_window` | 81.337 | 51.179 | 67.768 | **49.988** | 71.612 | 52.370 |
| `bloom_filter` | 45.503 | **20.684** | 49.219 | 24.609 | 50.303 | 23.463 |
| `hash_join` | 81.326 | **45.190** | 75.521 | 49.429 | 83.786 | 54.237 |
| `sieve` | 61.795 | 33.974 | 70.782 | 39.132 | 57.025 | **30.486** |
| `fib` | 72.796 | 50.921 | 73.522 | 44.376 | 87.295 | **39.514** |
| `collatz` | 49.355 | **24.669** | 48.517 | 31.128 | 54.364 | 28.116 |
| `matmul` | 61.036 | 38.770 | 55.728 | 36.072 | 63.601 | **35.066** |
| `json_parse` | 56.448 | 33.024 | 39.856 | **21.629** | 62.069 | 28.331 |
| `nbody` | 80.061 | 60.214 | 74.603 | **54.450** | 81.835 | 55.626 |
| `chacha20` | 93.853 | **51.929** | 75.602 | 60.438 | 83.770 | 60.676 |
| `poly1305` | 151.192 | 74.751 | 148.120 | **68.659** | 176.784 | 70.042 |
| `blake2b` | 102.945 | **69.807** | 117.696 | 98.550 | 143.998 | 117.192 |
| `sha512` | 102.968 | **68.638** | 100.407 | 76.004 | 100.310 | 78.705 |
| `x25519` | 340.827 | **181.660** | 437.279 | 189.125 | 546.945 | 189.825 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.346_ | _0.3_ | _2.1_ | _0.4_ | _0.1_ |
| `lcg` | 47.429 | 0.7 | 1.1 | 0.7 | 0.7 |
| `packet_classifier` | 58.270 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 54.808 | 0.6 | 1.2 | 0.7 | 0.6 |
| `histogram_bins` | 49.455 | 0.6 | 1.1 | 0.7 | 0.6 |
| `prefix_scan` | 12.466 | 0.3 | 0.5 | 0.5 | 0.4 |
| `binary_search` | 57.461 | 0.6 | 1.4 | 0.7 | 0.7 |
| `sort_window` | 51.179 | 0.6 | 1.7 | 0.7 | 0.7 |
| `bloom_filter` | 20.684 | 0.5 | 1.2 | 0.5 | 0.5 |
| `hash_join` | 45.190 | 0.6 | 1.6 | 0.7 | 0.6 |
| `sieve` | 33.974 | 0.5 | 1.6 | 0.6 | 0.5 |
| `fib` | 50.921 | 0.7 | 1.5 | 0.6 | 0.5 |
| `collatz` | 24.669 | 0.5 | 1.8 | 0.6 | 0.5 |
| `matmul` | 38.770 | 0.6 | 0.9 | 0.6 | 0.6 |
| `json_parse` | 33.024 | 0.6 | 3.9 | 0.5 | 0.5 |
| `nbody` | 60.214 | 0.8 | 1.3 | 0.7 | 0.7 |
| `chacha20` | 51.929 | 0.6 | 6.0 | 0.8 | 0.7 |
| `poly1305` | 74.751 | 0.5 | 6.0 | 0.5 | 0.4 |
| `blake2b` | 69.807 | 0.7 | 1.4 | 0.8 | 0.8 |
| `sha512` | 68.638 | 0.7 | 1.4 | 0.8 | 0.8 |
| `x25519` | 181.660 | 0.5 | 3.7 | 0.4 | 0.3 |

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
| `ring_write` | 18 | 26 | 16 | 915 | 4432 | 2124 |
| `histogram_bins` | 18 | 26 | 16 | 916 | 4432 | 2124 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4432 | 2124 |
| `binary_search` | 17 | 26 | 16 | 916 | 4433 | 2125 |
| `sort_window` | 17 | 27 | 16 | 917 | 4432 | 2125 |
| `bloom_filter` | 18 | 26 | 16 | 917 | 4432 | 2124 |
| `hash_join` | 26 | 28 | 16 | 923 | 4434 | 2127 |
| `sieve` | 18 | 26 | 16 | 916 | 4431 | 2124 |
| `fib` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `collatz` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `matmul` | 18 | 26 | 16 | 917 | 4432 | 2125 |
| `json_parse` | 50 | 53 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 17 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 57 | 48 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 49 | 35 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 41 | 43 | 16 | 925 | 4435 | 2127 |
| `sha512` | 36 | 40 | 16 | 922 | 4433 | 2126 |
| `x25519` | 40 | 47 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _319_ | _+7922 %_ | _12.565_ | _153.977_ | _+1125 %_ |
| `lcg` | 26 | 319 | +1118 % | 71.341 | 188.681 | +164 % |
| `packet_classifier` | 26 | 319 | +1121 % | 86.057 | 207.071 | +141 % |
| `ring_write` | 26 | 320 | +1119 % | 84.697 | 209.525 | +147 % |
| `histogram_bins` | 26 | 320 | +1116 % | 83.181 | 206.549 | +148 % |
| `prefix_scan` | 27 | 320 | +1103 % | 39.049 | 158.010 | +305 % |
| `binary_search` | 26 | 319 | +1114 % | 96.266 | 210.745 | +119 % |
| `sort_window` | 27 | 320 | +1104 % | 81.337 | 190.900 | +135 % |
| `bloom_filter` | 26 | 320 | +1109 % | 45.503 | 166.222 | +265 % |
| `hash_join` | 28 | 322 | +1038 % | 81.326 | 197.171 | +142 % |
| `sieve` | 26 | 320 | +1118 % | 61.795 | 175.844 | +185 % |
| `fib` | 26 | 319 | +1122 % | 72.796 | 190.439 | +162 % |
| `collatz` | 26 | 319 | +1122 % | 49.355 | 170.046 | +245 % |
| `matmul` | 26 | 320 | +1107 % | 61.036 | 179.255 | +194 % |
| `json_parse` | 53 | 340 | +546 % | 56.448 | 172.688 | +206 % |
| `nbody` | 28 | 321 | +1045 % | 80.061 | 198.321 | +148 % |
| `chacha20` | 48 | 365 | +662 % | 93.853 | 227.572 | +142 % |
| `poly1305` | 35 | 347 | +902 % | 151.192 | 285.975 | +89 % |
| `blake2b` | 43 | 332 | +678 % | 102.945 | 207.782 | +102 % |
| `sha512` | 40 | 329 | +727 % | 102.968 | 227.302 | +121 % |
| `x25519` | 47 | 339 | +614 % | 340.827 | 467.631 | +37 % |

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
| _(floor: empty program)_ | _4.751_ | _123.833_ | _55.985_ | _64.608_ | _45.311_ | _56.366_ | _70.727_ |
| `lcg` | 5.128 | 142.271 | 57.530 | 72.902 | 45.521 | 61.439 | 76.857 |
| `packet_classifier` | 5.199 | 143.706 | 56.115 | 74.998 | 45.557 | 62.691 | 77.416 |
| `ring_write` | 16.079 | 156.540 | 70.157 | 75.459 | 46.572 | 63.486 | 78.441 |
| `histogram_bins` | 16.231 | 162.108 | 71.254 | 78.237 | 45.093 | 66.615 | 79.294 |
| `prefix_scan` | 16.161 | 161.902 | 72.137 | 78.506 | 45.234 | 65.197 | 79.838 |
| `binary_search` | 16.307 | 160.127 | 70.437 | 76.674 | 46.206 | 68.277 | 82.486 |
| `sort_window` | 16.494 | 166.900 | 81.896 | 83.146 | 45.838 | 71.957 | 86.355 |
| `bloom_filter` | 16.967 | 166.315 | 74.173 | 82.817 | 45.212 | 68.521 | 83.225 |
| `hash_join` | 20.513 | 274.260 | 85.097 | 121.486 | 46.532 | 102.294 | 117.386 |
| `sieve` | 16.580 | 162.562 | 70.211 | 83.359 | 46.002 | 72.464 | 85.033 |
| `fib` | 5.243 | 141.439 | 56.514 | 72.534 | 45.665 | 62.027 | 77.036 |
| `collatz` | 5.410 | 146.278 | 56.886 | 73.580 | 45.458 | 62.879 | 77.757 |
| `matmul` | 17.791 | 166.827 | 74.889 | 85.809 | 45.324 | 82.805 | 94.519 |
| `json_parse` | 51.919 | 739.024 | 185.438 | 127.004 | 46.287 | 162.186 | 145.808 |
| `nbody` | 18.916 | 179.171 | 84.961 | 102.059 | 46.133 | 86.655 | 100.801 |
| `chacha20` | 59.003 | 840.661 | 195.036 | 117.299 | 46.543 | 105.499 | 117.027 |
| `poly1305` | 44.521 | 615.373 | 130.646 | 120.001 | 45.278 | 113.436 | 124.446 |
| `blake2b` | 40.275 | 558.630 | 119.658 | 117.778 | 46.301 | 117.730 | 126.665 |
| `sha512` | 41.793 | 503.276 | 132.894 | 108.894 | 48.032 | 108.590 | 119.796 |
| `x25519` | 41.996 | 999.819 | 134.181 | 783.551 | 48.593 | 642.589 | 663.866 |

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
