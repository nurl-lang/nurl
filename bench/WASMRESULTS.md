# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-13T17:30:14Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `19238cfe055f72ca1b3336f086168437df0ec0ac` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43472153713 |
| NURL | `v0.91.1-111-g19238cfe` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.9), built from this repo |
| C → wasm | `zig 0.17.1 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.4 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _3.514_ | _12.894_ | _3.7_ | _3.579_ | _8.948_ | _2.5_ | _3.681_ | _36.329_ | _9.9_ |
| `lcg` | 41.503 | 67.733 | 1.6 | 41.470 | 66.831 | 1.6 | 41.676 | 76.925 | 1.8 |
| `packet_classifier` | 58.729 | 79.448 | 1.4 | 58.620 | 79.664 | 1.4 | 59.017 | 89.323 | 1.5 |
| `ring_write` | 44.752 | 81.109 | 1.8 | 44.642 | 79.019 | 1.8 | 44.886 | 88.704 | 2.0 |
| `histogram_bins` | 41.701 | 81.473 | 2.0 | 42.034 | 74.778 | 1.8 | 43.941 | 87.211 | 2.0 |
| `prefix_scan` | 24.237 | 39.190 | 1.6 | 24.212 | 41.265 | 1.7 | 24.340 | 47.576 | 2.0 |
| `binary_search` | 37.988 | 89.330 | 2.4 | 38.869 | 91.579 | 2.4 | 47.362 | 101.235 | 2.1 |
| `sort_window` | 29.616 | 69.630 | 2.4 | 66.751 | 60.057 | 0.9 | 29.276 | 74.613 | 2.5 |
| `bloom_filter` | 17.641 | 53.180 | 3.0 | 20.526 | 49.143 | 2.4 | 20.814 | 59.135 | 2.8 |
| `hash_join` | 29.530 | 81.887 | 2.8 | 32.413 | 70.836 | 2.2 | 32.476 | 90.975 | 2.8 |
| `sieve` | 27.634 | 62.736 | 2.3 | 27.744 | 76.130 | 2.7 | 27.827 | 72.861 | 2.6 |
| `fib` | 30.575 | 77.127 | 2.5 | 30.539 | 79.473 | 2.6 | 27.732 | 84.511 | 3.0 |
| `collatz` | 14.479 | 46.341 | 3.2 | 14.527 | 47.409 | 3.3 | 14.464 | 56.082 | 3.9 |
| `matmul` | 36.192 | 58.912 | 1.6 | 35.927 | 57.852 | 1.6 | 36.383 | 67.382 | 1.9 |
| `json_parse` | 8.374 | 56.237 | 6.7 | 13.461 | 40.370 | 3.0 | 18.750 | 62.944 | 3.4 |
| `nbody` | 43.096 | 85.698 | 2.0 | 48.355 | 69.657 | 1.4 | 41.354 | 79.250 | 1.9 |
| `safe_record_array` | 64.084 | 125.990 | 2.0 | 56.973 | 98.181 | 1.7 | 68.755 | 106.779 | 1.6 |
| `payload_state_machine` | 91.124 | 233.773 | 2.6 | 74.621 | 137.741 | 1.8 | 75.625 | 142.339 | 1.9 |
| `captured_closure_queue` | 107.324 | 201.249 | 1.9 | 87.695 | 173.104 | 2.0 | 98.616 | 191.606 | 1.9 |
| `dynamic_method_mix` | 118.002 | 240.711 | 2.0 | 131.433 | 225.095 | 1.7 | 120.090 | 235.024 | 2.0 |
| `csv_table_pipeline` | 90.591 | 206.125 | 2.3 | 103.504 | 191.502 | 1.9 | 86.794 | 181.472 | 2.1 |
| `chacha20` | 9.904 | 80.577 | 8.1 | 40.330 | 79.892 | 2.0 | 41.771 | 87.011 | 2.1 |
| `poly1305` | 14.442 | 151.120 | 10.5 | 23.293 | 145.564 | 6.2 | 23.612 | 172.853 | 7.3 |
| `blake2b` | 46.370 | 90.256 | 1.9 | 68.432 | 104.777 | 1.5 | 71.684 | 129.891 | 1.8 |
| `sha512` | 47.946 | 95.987 | 2.0 | 52.204 | 86.403 | 1.7 | 51.585 | 102.240 | 2.0 |
| `x25519` | 34.386 | 331.626 | 9.6 | 57.740 | 456.005 | 7.9 | 55.707 | 532.715 | 9.6 |

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
| `lcg` | 1.4 | — | 1.5 | 1.1 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.7 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.8 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.6 | — |
| `binary_search` | 2.2 | — | 2.3 | 1.5 |
| `sort_window` | 2.2 | — | 0.8 | 1.5 |
| `bloom_filter` | 2.9 | — | 2.4 | — |
| `hash_join` | 2.7 | — | 2.1 | 1.9 |
| `sieve` | 2.1 | — | 2.8 | 1.5 |
| `fib` | 2.4 | — | 2.6 | 2.0 |
| `collatz` | 3.1 | — | 3.5 | — |
| `matmul` | 1.4 | — | 1.5 | — |
| `json_parse` | 8.9 | — | 3.2 | — |
| `nbody` | 1.8 | — | 1.4 | 1.1 |
| `safe_record_array` | 1.9 | — | 1.7 | 1.1 |
| `payload_state_machine` | 2.5 | 2.3 | 1.8 | 1.5 |
| `captured_closure_queue` | 1.8 | 1.7 | 2.0 | 1.6 |
| `dynamic_method_mix` | 2.0 | 1.8 | 1.7 | 1.7 |
| `csv_table_pipeline` | 2.2 | 2.0 | 1.8 | 1.7 |
| `chacha20` | 10.6 | — | 1.9 | 1.3 |
| `poly1305` | 12.6 | — | 6.9 | 6.8 |
| `blake2b` | 1.8 | — | 1.5 | 1.4 |
| `sha512` | 1.9 | — | 1.6 | 1.4 |
| `x25519` | 10.3 | 9.9 | 8.3 | 9.5 |

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
| _(floor: empty program)_ | _12.894_ | _6.171_ | _8.948_ | _**5.961**_ | _36.329_ | _7.455_ |
| `lcg` | 67.733 | **45.382** | 66.831 | 49.175 | 76.925 | 49.695 |
| `packet_classifier` | 79.448 | **54.423** | 79.664 | 58.660 | 89.323 | 59.132 |
| `ring_write` | 81.109 | **51.409** | 79.019 | 55.654 | 88.704 | 56.643 |
| `histogram_bins` | 81.473 | **46.658** | 74.778 | 53.326 | 87.211 | 55.622 |
| `prefix_scan` | 39.190 | **16.519** | 41.265 | 26.764 | 47.576 | 23.704 |
| `binary_search` | 89.330 | **57.520** | 91.579 | 61.128 | 101.235 | 67.010 |
| `sort_window` | 69.630 | **54.295** | 60.057 | 55.043 | 74.613 | 54.692 |
| `bloom_filter` | 53.180 | 26.669 | 49.143 | 26.656 | 59.135 | **26.350** |
| `hash_join` | 81.887 | **46.873** | 70.836 | 51.708 | 90.975 | 52.078 |
| `sieve` | 62.736 | 40.784 | 76.130 | **39.219** | 72.861 | 43.412 |
| `fib` | 77.127 | **40.472** | 79.473 | 45.156 | 84.511 | 42.194 |
| `collatz` | 46.341 | **25.010** | 47.409 | 29.485 | 56.082 | 29.593 |
| `matmul` | 58.912 | **34.751** | 57.852 | 36.052 | 67.382 | 37.112 |
| `json_parse` | 56.237 | 31.774 | 40.370 | **24.933** | 62.944 | 39.897 |
| `nbody` | 85.698 | **52.261** | 69.657 | 52.566 | 79.250 | 57.255 |
| `safe_record_array` | 125.990 | 102.186 | 98.181 | 83.272 | 106.779 | **82.739** |
| `payload_state_machine` | 233.773 | 225.815 | 137.741 | **112.937** | 142.339 | 116.883 |
| `captured_closure_queue` | 201.249 | 198.252 | 173.104 | **167.418** | 191.606 | 184.324 |
| `dynamic_method_mix` | 240.711 | 249.215 | **225.095** | 251.541 | 235.024 | 259.847 |
| `csv_table_pipeline` | 206.125 | 175.177 | 191.502 | 165.779 | 181.472 | **154.166** |
| `chacha20` | 80.577 | **51.324** | 79.892 | 62.839 | 87.011 | 64.983 |
| `poly1305` | 151.120 | 84.082 | 145.564 | 68.738 | 172.853 | **68.388** |
| `blake2b` | 90.256 | **74.030** | 104.777 | 95.276 | 129.891 | 115.893 |
| `sha512` | 95.987 | 80.575 | 86.403 | **75.110** | 102.240 | 76.375 |
| `x25519` | 331.626 | **160.918** | 456.005 | 187.525 | 532.715 | 192.014 |

`nwasm` is faster than the reference runtime on 24 of 25 NURL modules,
24 of 25 C modules and 24 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _6.171_ | _0.5_ | _1.8_ | _0.7_ | _0.2_ |
| `lcg` | 45.382 | 0.7 | 1.1 | 0.7 | 0.6 |
| `packet_classifier` | 54.423 | 0.7 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 51.409 | 0.6 | 1.1 | 0.7 | 0.6 |
| `histogram_bins` | 46.658 | 0.6 | 1.1 | 0.7 | 0.6 |
| `prefix_scan` | 16.519 | 0.4 | 0.7 | 0.6 | 0.5 |
| `binary_search` | 57.520 | 0.6 | 1.5 | 0.7 | 0.7 |
| `sort_window` | 54.295 | 0.8 | 1.8 | 0.9 | 0.7 |
| `bloom_filter` | 26.669 | 0.5 | 1.5 | 0.5 | 0.4 |
| `hash_join` | 46.873 | 0.6 | 1.6 | 0.7 | 0.6 |
| `sieve` | 40.784 | 0.7 | 1.5 | 0.5 | 0.6 |
| `fib` | 40.472 | 0.5 | 1.3 | 0.6 | 0.5 |
| `collatz` | 25.010 | 0.5 | 1.7 | 0.6 | 0.5 |
| `matmul` | 34.751 | 0.6 | 1.0 | 0.6 | 0.6 |
| `json_parse` | 31.774 | 0.6 | 3.8 | 0.6 | 0.6 |
| `nbody` | 52.261 | 0.6 | 1.2 | 0.8 | 0.7 |
| `safe_record_array` | 102.186 | 0.8 | 1.6 | 0.8 | 0.8 |
| `payload_state_machine` | 225.815 | 1.0 | 2.5 | 0.8 | 0.8 |
| `captured_closure_queue` | 198.252 | 1.0 | 1.8 | 1.0 | 1.0 |
| `dynamic_method_mix` | 249.215 | 1.0 | 2.1 | 1.1 | 1.1 |
| `csv_table_pipeline` | 175.177 | 0.8 | 1.9 | 0.9 | 0.8 |
| `chacha20` | 51.324 | 0.6 | 5.2 | 0.8 | 0.7 |
| `poly1305` | 84.082 | 0.6 | 5.8 | 0.5 | 0.4 |
| `blake2b` | 74.030 | 0.8 | 1.6 | 0.9 | 0.9 |
| `sha512` | 80.575 | 0.8 | 1.7 | 0.9 | 0.7 |
| `x25519` | 160.918 | 0.5 | 4.7 | 0.4 | 0.4 |

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
| `lcg` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `packet_classifier` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `ring_write` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `histogram_bins` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `prefix_scan` | 11 | 25 | 6 | 931 | 4388 | 2138 |
| `binary_search` | 12 | 25 | 7 | 931 | 4389 | 2138 |
| `sort_window` | 11 | 25 | 6 | 931 | 4388 | 2138 |
| `bloom_filter` | 11 | 25 | 6 | 931 | 4388 | 2137 |
| `hash_join` | 18 | 27 | 8 | 938 | 4390 | 2140 |
| `sieve` | 11 | 25 | 7 | 931 | 4388 | 2137 |
| `fib` | 11 | 25 | 6 | 930 | 4387 | 2137 |
| `collatz` | 11 | 25 | 6 | 930 | 4387 | 2137 |
| `matmul` | 12 | 25 | 7 | 931 | 4388 | 2138 |
| `json_parse` | 36 | 45 | 10 | 1021 | 4402 | 2168 |
| `nbody` | 13 | 27 | 8 | 934 | 4389 | 2138 |
| `safe_record_array` | 28 | 34 | 7 | 933 | 4389 | 2139 |
| `payload_state_machine` | 22 | 31 | 7 | 935 | 4390 | 2139 |
| `captured_closure_queue` | 34 | 36 | 9 | 939 | 4395 | 2142 |
| `dynamic_method_mix` | 33 | 35 | 9 | 937 | 4393 | 2141 |
| `csv_table_pipeline` | 64 | 68 | 17 | 965 | 4400 | 2148 |
| `chacha20` | 45 | 39 | 7 | 937 | 4389 | 2138 |
| `poly1305` | 34 | 33 | 7 | 935 | 4389 | 2138 |
| `blake2b` | 35 | 41 | 9 | 940 | 4391 | 2140 |
| `sha512` | 33 | 39 | 8 | 936 | 4390 | 2139 |
| `x25519` | 42 | 47 | 39 | 1176 | 4421 | 2192 |

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
| _(floor: empty program)_ | _4_ | _366_ | _+9308 %_ | _12.894_ | _168.104_ | _+1204 %_ |
| `lcg` | 25 | 366 | +1369 % | 67.733 | 209.860 | +210 % |
| `packet_classifier` | 25 | 366 | +1373 % | 79.448 | 223.480 | +181 % |
| `ring_write` | 25 | 366 | +1370 % | 81.109 | 224.881 | +177 % |
| `histogram_bins` | 25 | 366 | +1366 % | 81.473 | 226.039 | +177 % |
| `prefix_scan` | 25 | 366 | +1349 % | 39.190 | 180.191 | +360 % |
| `binary_search` | 25 | 366 | +1363 % | 89.330 | 233.229 | +161 % |
| `sort_window` | 25 | 367 | +1350 % | 69.630 | 215.770 | +210 % |
| `bloom_filter` | 25 | 366 | +1357 % | 53.180 | 192.002 | +261 % |
| `hash_join` | 27 | 369 | +1266 % | 81.887 | 219.633 | +168 % |
| `sieve` | 25 | 366 | +1369 % | 62.736 | 199.896 | +219 % |
| `fib` | 25 | 366 | +1375 % | 77.127 | 217.096 | +181 % |
| `collatz` | 25 | 366 | +1374 % | 46.341 | 187.863 | +305 % |
| `matmul` | 25 | 366 | +1354 % | 58.912 | 199.581 | +239 % |
| `json_parse` | 45 | 381 | +747 % | 56.237 | 188.154 | +235 % |
| `nbody` | 27 | 368 | +1275 % | 85.698 | 213.291 | +149 % |
| `safe_record_array` | 34 | 369 | +987 % | 125.990 | 256.785 | +104 % |
| `payload_state_machine` | 31 | 370 | +1075 % | 233.773 | 373.869 | +60 % |
| `captured_closure_queue` | 36 | 371 | +921 % | 201.249 | 339.618 | +69 % |
| `dynamic_method_mix` | 35 | 371 | +951 % | 240.711 | 377.852 | +57 % |
| `csv_table_pipeline` | 68 | 391 | +478 % | 206.125 | 339.768 | +65 % |
| `chacha20` | 39 | 447 | +1042 % | 80.577 | 258.561 | +221 % |
| `poly1305` | 33 | 407 | +1129 % | 151.120 | 302.451 | +100 % |
| `blake2b` | 41 | 379 | +823 % | 90.256 | 235.268 | +161 % |
| `sha512` | 39 | 377 | +860 % | 95.987 | 233.369 | +143 % |
| `x25519` | 47 | 398 | +756 % | 331.626 | 473.402 | +43 % |

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
| _(floor: empty program)_ | _7.105_ | _77.390_ | _73.956_ | _32.650_ | _45.205_ | _59.116_ | _72.602_ |
| `lcg` | 7.543 | 88.439 | 78.164 | 38.296 | 44.778 | 62.493 | 77.419 |
| `packet_classifier` | 7.457 | 89.448 | 78.342 | 39.944 | 45.325 | 63.811 | 77.901 |
| `ring_write` | 14.521 | 98.109 | 93.863 | 39.975 | 44.967 | 67.066 | 79.451 |
| `histogram_bins` | 14.876 | 101.559 | 98.374 | 42.279 | 44.661 | 66.780 | 80.596 |
| `prefix_scan` | 14.648 | 101.481 | 93.524 | 42.971 | 49.061 | 67.795 | 85.547 |
| `binary_search` | 15.056 | 101.487 | 93.615 | 40.658 | 44.217 | 68.722 | 84.359 |
| `sort_window` | 15.123 | 105.979 | 102.928 | 45.008 | 44.531 | 74.900 | 89.786 |
| `bloom_filter` | 15.850 | 107.792 | 103.148 | 44.498 | 45.059 | 72.077 | 85.379 |
| `hash_join` | 19.804 | 177.374 | 161.587 | 71.596 | 45.112 | 106.865 | 119.092 |
| `sieve` | 15.172 | 105.308 | 101.273 | 48.641 | 46.373 | 77.068 | 89.405 |
| `fib` | 7.727 | 89.440 | 76.734 | 39.274 | 44.341 | 64.506 | 78.189 |
| `collatz` | 7.776 | 89.625 | 82.866 | 39.965 | 45.781 | 65.070 | 79.004 |
| `matmul` | 15.265 | 106.201 | 100.697 | 48.716 | 44.874 | 90.052 | 98.500 |
| `json_parse` | 50.363 | 342.082 | 356.035 | 72.641 | 45.790 | 166.224 | 154.442 |
| `nbody` | 17.968 | 119.086 | 117.372 | 62.007 | 44.327 | 93.922 | 100.506 |
| `safe_record_array` | 19.493 | 218.811 | 139.092 | 48.737 | 45.102 | 88.266 | 100.267 |
| `payload_state_machine` | 28.253 | 192.391 | 170.170 | 51.789 | 45.227 | 92.632 | 102.767 |
| `captured_closure_queue` | 22.818 | 263.637 | 175.260 | 56.068 | 44.604 | 119.225 | 120.151 |
| `dynamic_method_mix` | 22.405 | 261.156 | 174.439 | 54.765 | 44.731 | 110.171 | 120.399 |
| `csv_table_pipeline` | 89.732 | 599.864 | 593.139 | 157.640 | 44.384 | 246.196 | 253.544 |
| `chacha20` | 72.336 | 554.975 | 858.013 | 66.486 | 45.145 | 106.006 | 121.167 |
| `poly1305` | 59.470 | 386.683 | 431.802 | 72.727 | 45.737 | 115.064 | 130.938 |
| `blake2b` | 38.055 | 349.728 | 287.080 | 66.530 | 45.411 | 120.894 | 130.666 |
| `sha512` | 37.011 | 374.163 | 273.913 | 60.775 | 46.869 | 106.566 | 119.706 |
| `x25519` | 54.774 | 1331.403 | 902.373 | 587.157 | 45.672 | 651.758 | 684.715 |

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
| `safe_record_array` | `7272179836431339923` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `payload_state_machine` | `7410019181044824385` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `captured_closure_queue` | `1139091110298229923` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `dynamic_method_mix` | `1376727108579200197` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `csv_table_pipeline` | `4173891341820504351` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
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
