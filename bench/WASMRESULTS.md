# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-13T20:31:10Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366636 KiB |
| Commit | `ab45d9db114a58fdab60f618c679e8af95643b5d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43501246138 |
| NURL | `v0.91.1-112-gab45d9db` |
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
| C/Rust on the NURL interpreter | no (add --nwasm-all-langs) |
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
| _(floor: empty program)_ | _3.415_ | _12.286_ | _3.6_ | _3.549_ | _7.768_ | _2.2_ | _3.420_ | _30.599_ | _8.9_ |
| `lcg` | 36.658 | 57.390 | 1.6 | 36.635 | 58.113 | 1.6 | 36.909 | 63.345 | 1.7 |
| `packet_classifier` | 51.690 | 68.283 | 1.3 | 51.700 | 70.029 | 1.4 | 51.908 | 75.834 | 1.5 |
| `ring_write` | 39.321 | 67.870 | 1.7 | 39.378 | 69.082 | 1.8 | 39.529 | 74.805 | 1.9 |
| `histogram_bins` | 37.150 | 70.053 | 1.9 | 37.010 | 64.974 | 1.8 | 37.138 | 71.825 | 1.9 |
| `prefix_scan` | 21.529 | 34.068 | 1.6 | 21.489 | 33.476 | 1.6 | 21.517 | 41.195 | 1.9 |
| `binary_search` | 28.905 | 79.977 | 2.8 | 28.426 | 83.667 | 2.9 | 34.309 | 81.589 | 2.4 |
| `sort_window` | 26.242 | 63.668 | 2.4 | 41.646 | 52.805 | 1.3 | 25.902 | 59.428 | 2.3 |
| `bloom_filter` | 15.882 | 40.383 | 2.5 | 18.322 | 40.611 | 2.2 | 18.475 | 50.468 | 2.7 |
| `hash_join` | 23.323 | 69.845 | 3.0 | 26.603 | 66.861 | 2.5 | 26.864 | 66.790 | 2.5 |
| `sieve` | 21.592 | 51.238 | 2.4 | 21.503 | 53.434 | 2.5 | 21.400 | 60.352 | 2.8 |
| `fib` | 25.058 | 60.932 | 2.4 | 25.077 | 59.363 | 2.4 | 24.251 | 65.454 | 2.7 |
| `collatz` | 12.868 | 40.431 | 3.1 | 12.891 | 41.545 | 3.2 | 12.918 | 47.861 | 3.7 |
| `matmul` | 38.185 | 53.894 | 1.4 | 38.320 | 50.511 | 1.3 | 38.882 | 53.597 | 1.4 |
| `json_parse` | 6.868 | 45.129 | 6.6 | 11.293 | 34.481 | 3.1 | 15.726 | 50.443 | 3.2 |
| `nbody` | 38.325 | 60.399 | 1.6 | 41.078 | 59.861 | 1.5 | 36.494 | 65.616 | 1.8 |
| `safe_record_array` | 55.284 | 101.238 | 1.8 | 49.439 | 88.032 | 1.8 | 59.045 | 88.821 | 1.5 |
| `payload_state_machine` | 68.706 | 182.925 | 2.7 | 65.096 | 118.839 | 1.8 | 64.866 | 120.551 | 1.9 |
| `captured_closure_queue` | 94.211 | 171.050 | 1.8 | 74.330 | 148.440 | 2.0 | 87.054 | 162.168 | 1.9 |
| `dynamic_method_mix` | 108.050 | 204.029 | 1.9 | 110.711 | 185.362 | 1.7 | 103.083 | 198.133 | 1.9 |
| `csv_table_pipeline` | 77.069 | 170.376 | 2.2 | 89.068 | 149.219 | 1.7 | 75.254 | 138.310 | 1.8 |
| `chacha20` | 6.577 | 67.036 | 10.2 | 34.801 | 63.611 | 1.8 | 37.691 | 70.614 | 1.9 |
| `poly1305` | 13.082 | 121.339 | 9.3 | 20.867 | 112.907 | 5.4 | 20.960 | 137.264 | 6.5 |
| `blake2b` | 39.103 | 72.343 | 1.9 | 59.390 | 91.223 | 1.5 | 62.944 | 107.271 | 1.7 |
| `sha512` | 41.329 | 78.676 | 1.9 | 43.604 | 77.322 | 1.8 | 44.169 | 85.152 | 1.9 |
| `x25519` | 30.482 | 258.588 | 8.5 | 50.506 | 339.148 | 6.7 | 48.375 | 432.891 | 8.9 |

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
| `ring_write` | 1.5 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.2 | — | 1.4 | — |
| `binary_search` | 2.7 | — | 3.1 | 1.7 |
| `sort_window` | 2.3 | — | 1.2 | — |
| `bloom_filter` | 2.3 | — | 2.2 | — |
| `hash_join` | 2.9 | — | 2.6 | 1.5 |
| `sieve` | 2.1 | — | 2.5 | — |
| `fib` | 2.2 | — | 2.4 | 1.7 |
| `collatz` | 3.0 | — | 3.6 | — |
| `matmul` | 1.2 | — | 1.2 | — |
| `json_parse` | 9.5 | — | 3.4 | — |
| `nbody` | 1.4 | — | 1.4 | 1.1 |
| `safe_record_array` | 1.7 | — | 1.7 | 1.0 |
| `payload_state_machine` | 2.6 | 2.4 | 1.8 | 1.5 |
| `captured_closure_queue` | 1.7 | 1.6 | 2.0 | 1.6 |
| `dynamic_method_mix` | 1.8 | 1.6 | 1.7 | 1.7 |
| `csv_table_pipeline` | 2.1 | 1.9 | 1.7 | 1.5 |
| `chacha20` | — | — | 1.8 | 1.2 |
| `poly1305` | 11.3 | — | 6.1 | 6.1 |
| `blake2b` | 1.7 | — | 1.5 | 1.3 |
| `sha512` | 1.8 | — | 1.7 | 1.3 |
| `x25519` | 9.1 | 8.1 | 7.1 | 8.9 |

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
| _(floor: empty program)_ | _12.286_ | _**5.225**_ | _7.768_ | _SKIPPED_ | _30.599_ | _SKIPPED_ |
| `lcg` | 57.390 | **39.698** | 58.113 | SKIPPED | 63.345 | SKIPPED |
| `packet_classifier` | 68.283 | **48.105** | 70.029 | SKIPPED | 75.834 | SKIPPED |
| `ring_write` | 67.870 | **44.905** | 69.082 | SKIPPED | 74.805 | SKIPPED |
| `histogram_bins` | 70.053 | **41.034** | 64.974 | SKIPPED | 71.825 | SKIPPED |
| `prefix_scan` | 34.068 | **12.226** | 33.476 | SKIPPED | 41.195 | SKIPPED |
| `binary_search` | 79.977 | **47.654** | 83.667 | SKIPPED | 81.589 | SKIPPED |
| `sort_window` | 63.668 | **43.960** | 52.805 | SKIPPED | 59.428 | SKIPPED |
| `bloom_filter` | 40.383 | **18.267** | 40.611 | SKIPPED | 50.468 | SKIPPED |
| `hash_join` | 69.845 | **38.158** | 66.861 | SKIPPED | 66.790 | SKIPPED |
| `sieve` | 51.238 | **27.030** | 53.434 | SKIPPED | 60.352 | SKIPPED |
| `fib` | 60.932 | **31.409** | 59.363 | SKIPPED | 65.454 | SKIPPED |
| `collatz` | 40.431 | **21.501** | 41.545 | SKIPPED | 47.861 | SKIPPED |
| `matmul` | 53.894 | **32.578** | 50.511 | SKIPPED | 53.597 | SKIPPED |
| `json_parse` | 45.129 | **25.482** | 34.481 | SKIPPED | 50.443 | SKIPPED |
| `nbody` | 60.399 | **48.089** | 59.861 | SKIPPED | 65.616 | SKIPPED |
| `safe_record_array` | 101.238 | **82.667** | 88.032 | SKIPPED | 88.821 | SKIPPED |
| `payload_state_machine` | 182.925 | 170.084 | **118.839** | SKIPPED | 120.551 | SKIPPED |
| `captured_closure_queue` | 171.050 | 172.859 | **148.440** | SKIPPED | 162.168 | SKIPPED |
| `dynamic_method_mix` | 204.029 | 195.399 | **185.362** | SKIPPED | 198.133 | SKIPPED |
| `csv_table_pipeline` | 170.376 | 141.466 | 149.219 | SKIPPED | **138.310** | SKIPPED |
| `chacha20` | 67.036 | **41.587** | 63.611 | SKIPPED | 70.614 | SKIPPED |
| `poly1305` | 121.339 | **59.791** | 112.907 | SKIPPED | 137.264 | SKIPPED |
| `blake2b` | 72.343 | **54.368** | 91.223 | SKIPPED | 107.271 | SKIPPED |
| `sha512` | 78.676 | **54.864** | 77.322 | SKIPPED | 85.152 | SKIPPED |
| `x25519` | 258.588 | **134.876** | 339.148 | SKIPPED | 432.891 | SKIPPED |

`nwasm` is faster than the reference runtime on 24 of 25 NURL modules (the C
and Rust modules were not run on `nwasm` this time).

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _5.225_ | _0.4_ | _1.5_ | _—_ | _—_ |
| `lcg` | 39.698 | 0.7 | 1.1 | — | — |
| `packet_classifier` | 48.105 | 0.7 | 0.9 | — | — |
| `ring_write` | 44.905 | 0.7 | 1.1 | — | — |
| `histogram_bins` | 41.034 | 0.6 | 1.1 | — | — |
| `prefix_scan` | 12.226 | 0.4 | 0.6 | — | — |
| `binary_search` | 47.654 | 0.6 | 1.6 | — | — |
| `sort_window` | 43.960 | 0.7 | 1.7 | — | — |
| `bloom_filter` | 18.267 | 0.5 | 1.2 | — | — |
| `hash_join` | 38.158 | 0.5 | 1.6 | — | — |
| `sieve` | 27.030 | 0.5 | 1.3 | — | — |
| `fib` | 31.409 | 0.5 | 1.3 | — | — |
| `collatz` | 21.501 | 0.5 | 1.7 | — | — |
| `matmul` | 32.578 | 0.6 | 0.9 | — | — |
| `json_parse` | 25.482 | 0.6 | 3.7 | — | — |
| `nbody` | 48.089 | 0.8 | 1.3 | — | — |
| `safe_record_array` | 82.667 | 0.8 | 1.5 | — | — |
| `payload_state_machine` | 170.084 | 0.9 | 2.5 | — | — |
| `captured_closure_queue` | 172.859 | 1.0 | 1.8 | — | — |
| `dynamic_method_mix` | 195.399 | 1.0 | 1.8 | — | — |
| `csv_table_pipeline` | 141.466 | 0.8 | 1.8 | — | — |
| `chacha20` | 41.587 | 0.6 | 6.3 | — | — |
| `poly1305` | 59.791 | 0.5 | 4.6 | — | — |
| `blake2b` | 54.368 | 0.8 | 1.4 | — | — |
| `sha512` | 54.864 | 0.7 | 1.3 | — | — |
| `x25519` | 134.876 | 0.5 | 4.4 | — | — |

The C and Rust `nwasm` cells are `SKIPPED`: they are the cross-frontend
control — modules this runtime never saw during development, from two
other LLVM frontends — and running them costs about three times the
whole rest of the suite, so they are opt-in. `--nwasm-all-langs` fills
them in. Until it is run, this section says what the interpreter does
with NURL output and nothing about whether it is tuned for it.

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
| `json_parse` | 35 | 44 | 10 | 1021 | 4402 | 2168 |
| `nbody` | 13 | 27 | 8 | 934 | 4389 | 2138 |
| `safe_record_array` | 28 | 34 | 7 | 933 | 4389 | 2139 |
| `payload_state_machine` | 21 | 31 | 7 | 935 | 4390 | 2139 |
| `captured_closure_queue` | 34 | 36 | 9 | 939 | 4395 | 2142 |
| `dynamic_method_mix` | 33 | 35 | 9 | 937 | 4393 | 2141 |
| `csv_table_pipeline` | 64 | 67 | 17 | 965 | 4400 | 2148 |
| `chacha20` | 40 | 37 | 7 | 937 | 4389 | 2138 |
| `poly1305` | 34 | 33 | 7 | 935 | 4389 | 2138 |
| `blake2b` | 34 | 40 | 9 | 940 | 4391 | 2140 |
| `sha512` | 32 | 39 | 8 | 936 | 4390 | 2139 |
| `x25519` | 41 | 46 | 39 | 1176 | 4421 | 2192 |

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
| _(floor: empty program)_ | _4_ | _366_ | _+9308 %_ | _12.286_ | _133.277_ | _+985 %_ |
| `lcg` | 25 | 366 | +1369 % | 57.390 | 167.348 | +192 % |
| `packet_classifier` | 25 | 366 | +1373 % | 68.283 | 181.561 | +166 % |
| `ring_write` | 25 | 366 | +1370 % | 67.870 | 178.414 | +163 % |
| `histogram_bins` | 25 | 366 | +1366 % | 70.053 | 179.640 | +156 % |
| `prefix_scan` | 25 | 366 | +1349 % | 34.068 | 144.613 | +324 % |
| `binary_search` | 25 | 366 | +1363 % | 79.977 | 181.319 | +127 % |
| `sort_window` | 25 | 367 | +1350 % | 63.668 | 166.487 | +161 % |
| `bloom_filter` | 25 | 366 | +1357 % | 40.383 | 146.609 | +263 % |
| `hash_join` | 27 | 369 | +1266 % | 69.845 | 178.235 | +155 % |
| `sieve` | 25 | 366 | +1369 % | 51.238 | 161.213 | +215 % |
| `fib` | 25 | 366 | +1375 % | 60.932 | 168.504 | +177 % |
| `collatz` | 25 | 366 | +1374 % | 40.431 | 143.884 | +256 % |
| `matmul` | 25 | 366 | +1354 % | 53.894 | 157.159 | +192 % |
| `json_parse` | 44 | 380 | +754 % | 45.129 | 144.514 | +220 % |
| `nbody` | 27 | 368 | +1275 % | 60.399 | 170.783 | +183 % |
| `safe_record_array` | 34 | 369 | +987 % | 101.238 | 204.160 | +102 % |
| `payload_state_machine` | 31 | 369 | +1081 % | 182.925 | 287.757 | +57 % |
| `captured_closure_queue` | 36 | 371 | +921 % | 171.050 | 274.378 | +60 % |
| `dynamic_method_mix` | 35 | 371 | +951 % | 204.029 | 303.739 | +49 % |
| `csv_table_pipeline` | 67 | 390 | +479 % | 170.376 | 274.343 | +61 % |
| `chacha20` | 37 | 442 | +1091 % | 67.036 | 190.046 | +183 % |
| `poly1305` | 33 | 407 | +1145 % | 121.339 | 235.862 | +94 % |
| `blake2b` | 40 | 378 | +841 % | 72.343 | 182.612 | +152 % |
| `sha512` | 39 | 376 | +868 % | 78.676 | 189.368 | +141 % |
| `x25519` | 46 | 398 | +763 % | 258.588 | 352.960 | +36 % |

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
| _(floor: empty program)_ | _6.732_ | _72.079_ | _69.506_ | _33.706_ | _39.743_ | _51.359_ | _64.740_ |
| `lcg` | 9.995 | 84.686 | 68.052 | 62.429 | 40.647 | 57.430 | 69.712 |
| `packet_classifier` | 6.954 | 80.749 | 70.284 | 37.019 | 41.827 | 57.719 | 70.308 |
| `ring_write` | 12.992 | 89.376 | 83.173 | 37.522 | 58.821 | 58.604 | 70.799 |
| `histogram_bins` | 12.913 | 91.244 | 84.734 | 38.923 | 40.459 | 60.681 | 71.469 |
| `prefix_scan` | 13.107 | 91.598 | 83.761 | 39.774 | 40.695 | 61.069 | 74.220 |
| `binary_search` | 13.056 | 90.517 | 81.012 | 37.539 | 40.849 | 62.501 | 75.971 |
| `sort_window` | 13.279 | 94.419 | 87.582 | 41.355 | 69.073 | 66.324 | 77.970 |
| `bloom_filter` | 13.768 | 93.580 | 89.498 | 40.655 | 40.538 | 63.229 | 75.933 |
| `hash_join` | 17.077 | 155.273 | 134.497 | 60.518 | 40.390 | 90.651 | 102.887 |
| `sieve` | 13.247 | 92.192 | 86.549 | 43.397 | 41.354 | 67.986 | 79.348 |
| `fib` | 7.080 | 80.127 | 67.481 | 36.358 | 40.613 | 57.571 | 70.689 |
| `collatz` | 7.154 | 81.043 | 71.425 | 36.919 | 40.703 | 58.006 | 70.808 |
| `matmul` | 13.386 | 94.639 | 83.661 | 43.568 | 40.219 | 74.434 | 84.903 |
| `json_parse` | 40.674 | 278.614 | 281.326 | 62.224 | 41.471 | 140.012 | 129.328 |
| `nbody` | 14.602 | 98.926 | 100.095 | 52.073 | 40.888 | 76.806 | 89.616 |
| `safe_record_array` | 15.792 | 183.188 | 118.273 | 44.290 | 41.224 | 78.362 | 89.420 |
| `payload_state_machine` | 24.673 | 163.852 | 139.862 | 47.205 | 40.891 | 82.310 | 92.352 |
| `captured_closure_queue` | 20.318 | 228.062 | 145.888 | 50.722 | 41.575 | 101.126 | 104.247 |
| `dynamic_method_mix` | 18.668 | 217.567 | 144.566 | 47.931 | 40.085 | 95.695 | 100.335 |
| `csv_table_pipeline` | 75.261 | 516.787 | 481.741 | 126.445 | 40.606 | 207.234 | 210.781 |
| `chacha20` | 56.952 | 444.418 | 665.984 | 58.481 | 40.553 | 91.802 | 103.477 |
| `poly1305` | 46.462 | 311.006 | 336.024 | 61.518 | 39.997 | 97.227 | 109.168 |
| `blake2b` | 30.900 | 281.079 | 218.535 | 57.118 | 40.639 | 102.864 | 111.427 |
| `sha512` | 29.876 | 305.575 | 220.087 | 52.479 | 40.715 | 92.716 | 101.664 |
| `x25519` | 42.900 | 1035.800 | 697.265 | 458.743 | 90.913 | 514.176 | 546.420 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `safe_record_array` | `7272179836431339923` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `payload_state_machine` | `7410019181044824385` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `captured_closure_queue` | `1139091110298229923` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `dynamic_method_mix` | `1376727108579200197` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `csv_table_pipeline` | `4173891341820504351` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `chacha20` | `3720502699256473595` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `2498856793803813402` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `8590291023788228918` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sha512` | `7091519178481951668` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `x25519` | `6127485567278337128` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |

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
