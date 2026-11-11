# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-11T19:01:31Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-x100.json`](results/wasm-x100.json).

**Workload ×100.** Every benchmark below does 100 times its published
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
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16365616 KiB |
| Commit | `a013bfae93c3f95925d589a5909e374b9705b502` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43075264987 |
| NURL | `v0.91.0-7-ga013bfae` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.9), built from this repo |
| C → wasm | `zig 0.17.1 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.3 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Workload scale | ×100 — every benchmark's work multiplied by 100 before compilation |
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
| _(floor: empty program)_ | _2.560_ | _9.343_ | _3.6_ | _2.560_ | _6.688_ | _2.6_ | _2.640_ | _23.148_ | _8.8_ |
| `lcg` | 2968.073 | 2905.608 | 1.0 | 3020.303 | 2913.771 | 1.0 | 2964.070 | 3031.457 | 1.0 |
| `packet_classifier` | 4749.966 | 3775.538 | 0.8 | 4704.175 | 3836.569 | 0.8 | 4702.440 | 4027.026 | 0.9 |
| `ring_write` | 3227.476 | 3935.373 | 1.2 | 3323.417 | 4080.642 | 1.2 | 3237.035 | 4083.772 | 1.3 |
| `histogram_bins` | 3207.537 | 3758.762 | 1.2 | 2995.213 | 3752.798 | 1.3 | 2937.358 | 3905.144 | 1.3 |
| `prefix_scan` | 1571.638 | 586.718 | 0.4 | 1609.911 | 570.876 | 0.4 | 1687.854 | 561.779 | 0.3 |
| `binary_search` | 1890.307 | 4269.351 | 2.3 | 1869.236 | 3970.111 | 2.1 | 3234.224 | 4348.996 | 1.3 |
| `sort_window` | 3057.416 | 3089.145 | 1.0 | 4792.899 | 2454.397 | 0.5 | 2966.725 | 2635.336 | 0.9 |
| `bloom_filter` | 960.474 | 983.038 | 1.0 | 1014.726 | 867.333 | 0.9 | 1056.794 | 867.097 | 0.8 |
| `hash_join` | 1646.640 | 2953.530 | 1.8 | 1929.968 | 2438.177 | 1.3 | 2060.767 | 2964.213 | 1.4 |
| `sieve` | 3196.628 | 3928.693 | 1.2 | 3245.524 | 3373.976 | 1.0 | 3201.498 | 3372.250 | 1.1 |
| `fib` | 1629.948 | 2873.952 | 1.8 | 1809.580 | 2728.562 | 1.5 | 1842.551 | 2859.411 | 1.6 |
| `collatz` | 1571.842 | 1968.200 | 1.3 | 1595.398 | 1974.535 | 1.2 | 1664.414 | 2075.106 | 1.2 |
| `matmul` | 1222.392 | 1251.613 | 1.0 | 1371.649 | 1207.919 | 0.9 | 1370.532 | 1278.197 | 0.9 |
| `json_parse` | 271.288 | 695.945 | 2.6 | 550.912 | 460.899 | 0.8 | 783.739 | 669.171 | 0.9 |
| `nbody` | 2308.692 | 2392.849 | 1.0 | 2357.699 | 2196.024 | 0.9 | 2076.844 | 2225.023 | 1.1 |
| `safe_record_array` | 5051.352 | 6361.288 | 1.3 | 4293.305 | 5460.566 | 1.3 | 4638.763 | 5336.549 | 1.2 |
| `payload_state_machine` | 6899.736 | 13150.410 | 1.9 | 5991.743 | 9527.209 | 1.6 | 5792.845 | 9045.004 | 1.6 |
| `captured_closure_queue` | 8005.453 | 12934.099 | 1.6 | 6617.912 | 11864.752 | 1.8 | 7837.961 | 12648.690 | 1.6 |
| `dynamic_method_mix` | 8664.612 | 14365.626 | 1.7 | 8891.380 | 13532.430 | 1.5 | 8898.141 | 14012.554 | 1.6 |
| `csv_table_pipeline` | 5009.806 | 10716.295 | 2.1 | 6341.218 | 8146.443 | 1.3 | 5030.196 | 7915.096 | 1.6 |
| `chacha20` | 245.879 | 2314.448 | 9.4 | 2411.213 | 2959.386 | 1.2 | 2478.854 | 2953.424 | 1.2 |
| `poly1305` | 700.574 | 6079.954 | 8.7 | 1907.329 | 5987.605 | 3.1 | 1764.586 | 6979.286 | 4.0 |
| `blake2b` | 3192.634 | 3423.298 | 1.1 | 3829.892 | 3983.742 | 1.0 | 4025.952 | 5764.400 | 1.4 |
| `sha512` | 3017.189 | 3883.239 | 1.3 | 3330.096 | 4196.572 | 1.3 | 3604.952 | 4081.794 | 1.1 |
| `x25519` | 2046.824 | 15868.164 | 7.8 | 3327.532 | 18021.534 | 5.4 | 3210.293 | 23162.927 | 7.2 |

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
| `lcg` | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 0.8 | 0.8 | 0.8 | 0.9 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.3 |
| `histogram_bins` | 1.2 | 1.2 | 1.3 | 1.3 |
| `prefix_scan` | 0.4 | 0.3 | 0.4 | 0.3 |
| `binary_search` | 2.3 | 2.3 | 2.1 | 1.3 |
| `sort_window` | 1.0 | 1.0 | 0.5 | 0.9 |
| `bloom_filter` | 1.0 | 1.0 | 0.9 | 0.8 |
| `hash_join` | 1.8 | 1.8 | 1.3 | 1.4 |
| `sieve` | 1.2 | 1.2 | 1.0 | 1.0 |
| `fib` | 1.8 | 1.6 | 1.5 | 1.5 |
| `collatz` | 1.2 | 1.2 | 1.2 | 1.2 |
| `matmul` | 1.0 | 1.0 | 0.9 | 0.9 |
| `json_parse` | 2.6 | 2.5 | 0.8 | 0.8 |
| `nbody` | 1.0 | 1.0 | 0.9 | 1.1 |
| `safe_record_array` | 1.3 | 1.2 | 1.3 | 1.1 |
| `payload_state_machine` | 1.9 | 1.9 | 1.6 | 1.6 |
| `captured_closure_queue` | 1.6 | 1.6 | 1.8 | 1.6 |
| `dynamic_method_mix` | 1.7 | 1.6 | 1.5 | 1.6 |
| `csv_table_pipeline` | 2.1 | 2.1 | 1.3 | 1.6 |
| `chacha20` | 9.5 | 9.4 | 1.2 | 1.2 |
| `poly1305` | 8.7 | 8.5 | 3.1 | 3.9 |
| `blake2b` | 1.1 | 1.1 | 1.0 | 1.4 |
| `sha512` | 1.3 | 1.4 | 1.3 | 1.1 |
| `x25519` | 7.8 | 7.6 | 5.4 | 7.2 |

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
| _(floor: empty program)_ | _9.343_ | _3.422_ | _6.688_ | _**2.920**_ | _23.148_ | _4.242_ |
| `lcg` | 2905.608 | **2894.007** | 2913.771 | 2939.840 | 3031.457 | 2998.004 |
| `packet_classifier` | 3775.538 | **3628.427** | 3836.569 | 3647.073 | 4027.026 | 4146.308 |
| `ring_write` | 3935.373 | 3354.570 | 4080.642 | **3277.230** | 4083.772 | 3284.044 |
| `histogram_bins` | 3758.762 | 3412.713 | 3752.798 | 3022.961 | 3905.144 | **3010.332** |
| `prefix_scan` | 586.718 | **494.553** | 570.876 | 562.694 | 561.779 | 497.199 |
| `binary_search` | 4269.351 | 3661.935 | 3970.111 | **3515.474** | 4348.996 | 4030.668 |
| `sort_window` | 3089.145 | 3199.146 | 2454.397 | 2373.443 | 2635.336 | **2363.638** |
| `bloom_filter` | 983.038 | **730.043** | 867.333 | 786.726 | 867.097 | 754.946 |
| `hash_join` | 2953.530 | 2493.022 | **2438.177** | 2611.869 | 2964.213 | 2546.597 |
| `sieve` | 3928.693 | 3393.467 | 3373.976 | 3391.780 | **3372.250** | 3444.712 |
| `fib` | 2873.952 | 2078.593 | 2728.562 | 2073.289 | 2859.411 | **1983.894** |
| `collatz` | 1968.200 | 1862.008 | 1974.535 | 1839.178 | 2075.106 | **1828.954** |
| `matmul` | 1251.613 | **1207.446** | 1207.919 | 1212.211 | 1278.197 | 1229.806 |
| `json_parse` | 695.945 | 702.246 | 460.899 | **331.866** | 669.171 | 685.181 |
| `nbody` | 2392.849 | 2317.444 | **2196.024** | 2250.970 | 2225.023 | 2318.007 |
| `safe_record_array` | 6361.288 | 6449.383 | 5460.566 | 5858.906 | **5336.549** | 5573.859 |
| `payload_state_machine` | 13150.410 | 14587.240 | 9527.209 | 8982.609 | 9045.004 | **8725.167** |
| `captured_closure_queue` | 12934.099 | 13103.325 | **11864.752** | 11951.034 | 12648.690 | 12760.468 |
| `dynamic_method_mix` | 14365.626 | 15627.551 | **13532.430** | 15419.662 | 14012.554 | 14954.893 |
| `csv_table_pipeline` | 10716.295 | 10067.912 | 8146.443 | 8084.640 | 7915.096 | **7742.761** |
| `chacha20` | 2314.448 | **2294.124** | 2959.386 | 3080.074 | 2953.424 | 2972.215 |
| `poly1305` | 6079.954 | 5035.046 | 5987.605 | **4431.639** | 6979.286 | 4518.055 |
| `blake2b` | 3423.298 | **3347.825** | 3983.742 | 4630.830 | 5764.400 | 5597.432 |
| `sha512` | **3883.239** | 4049.950 | 4196.572 | 4349.896 | 4081.794 | 4233.655 |
| `x25519` | 15868.164 | **9458.805** | 18021.534 | 9680.412 | 23162.927 | 9492.405 |

`nwasm` is faster than the reference runtime on 18 of 25 NURL modules,
14 of 25 C modules and 16 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.422_ | _0.4_ | _1.3_ | _0.4_ | _0.2_ |
| `lcg` | 2894.007 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 3628.427 | 1.0 | 0.8 | 1.0 | 1.0 |
| `ring_write` | 3354.570 | 0.9 | 1.0 | 0.8 | 0.8 |
| `histogram_bins` | 3412.713 | 0.9 | 1.1 | 0.8 | 0.8 |
| `prefix_scan` | 494.553 | 0.8 | 0.3 | 1.0 | 0.9 |
| `binary_search` | 3661.935 | 0.9 | 1.9 | 0.9 | 0.9 |
| `sort_window` | 3199.146 | 1.0 | 1.0 | 1.0 | 0.9 |
| `bloom_filter` | 730.043 | 0.7 | 0.8 | 0.9 | 0.9 |
| `hash_join` | 2493.022 | 0.8 | 1.5 | 1.1 | 0.9 |
| `sieve` | 3393.467 | 0.9 | 1.1 | 1.0 | 1.0 |
| `fib` | 2078.593 | 0.7 | 1.3 | 0.8 | 0.7 |
| `collatz` | 1862.008 | 0.9 | 1.2 | 0.9 | 0.9 |
| `matmul` | 1207.446 | 1.0 | 1.0 | 1.0 | 1.0 |
| `json_parse` | 702.246 | 1.0 | 2.6 | 0.7 | 1.0 |
| `nbody` | 2317.444 | 1.0 | 1.0 | 1.0 | 1.0 |
| `safe_record_array` | 6449.383 | 1.0 | 1.3 | 1.1 | 1.0 |
| `payload_state_machine` | 14587.240 | 1.1 | 2.1 | 0.9 | 1.0 |
| `captured_closure_queue` | 13103.325 | 1.0 | 1.6 | 1.0 | 1.0 |
| `dynamic_method_mix` | 15627.551 | 1.1 | 1.8 | 1.1 | 1.1 |
| `csv_table_pipeline` | 10067.912 | 0.9 | 2.0 | 1.0 | 1.0 |
| `chacha20` | 2294.124 | 1.0 | 9.3 | 1.0 | 1.0 |
| `poly1305` | 5035.046 | 0.8 | 7.2 | 0.7 | 0.6 |
| `blake2b` | 3347.825 | 1.0 | 1.0 | 1.2 | 1.0 |
| `sha512` | 4049.950 | 1.0 | 1.3 | 1.0 | 1.0 |
| `x25519` | 9458.805 | 0.6 | 4.6 | 0.5 | 0.4 |

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
| `lcg` | 11 | 25 | 6 | 930 | 4431 | 2124 |
| `packet_classifier` | 11 | 25 | 6 | 930 | 4432 | 2124 |
| `ring_write` | 11 | 25 | 6 | 930 | 4432 | 2124 |
| `histogram_bins` | 11 | 25 | 6 | 930 | 4432 | 2124 |
| `prefix_scan` | 11 | 25 | 6 | 931 | 4432 | 2124 |
| `binary_search` | 12 | 25 | 7 | 931 | 4433 | 2125 |
| `sort_window` | 11 | 25 | 6 | 931 | 4432 | 2125 |
| `bloom_filter` | 11 | 25 | 6 | 931 | 4432 | 2124 |
| `hash_join` | 18 | 27 | 8 | 938 | 4434 | 2127 |
| `sieve` | 11 | 25 | 7 | 931 | 4431 | 2124 |
| `fib` | 11 | 25 | 6 | 930 | 4431 | 2124 |
| `collatz` | 11 | 25 | 6 | 930 | 4431 | 2124 |
| `matmul` | 12 | 25 | 7 | 931 | 4432 | 2125 |
| `json_parse` | 30 | 45 | 10 | 1021 | 4445 | 2154 |
| `nbody` | 13 | 27 | 8 | 934 | 4433 | 2125 |
| `safe_record_array` | 23 | 34 | 7 | 933 | 4433 | 2126 |
| `payload_state_machine` | 18 | 31 | 7 | 936 | 4434 | 2126 |
| `captured_closure_queue` | 31 | 36 | 9 | 939 | 4438 | 2129 |
| `dynamic_method_mix` | 30 | 35 | 9 | 937 | 4437 | 2128 |
| `csv_table_pipeline` | 59 | 68 | 17 | 965 | 4443 | 2134 |
| `chacha20` | 42 | 39 | 7 | 937 | 4432 | 2125 |
| `poly1305` | 29 | 33 | 7 | 935 | 4432 | 2125 |
| `blake2b` | 29 | 41 | 9 | 940 | 4435 | 2127 |
| `sha512` | 27 | 39 | 8 | 936 | 4433 | 2126 |
| `x25519` | 38 | 46 | 39 | 1176 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _365_ | _+9295 %_ | _9.343_ | _120.722_ | _+1192 %_ |
| `lcg` | 25 | 365 | +1367 % | 2905.608 | 3004.726 | +3 % |
| `packet_classifier` | 25 | 365 | +1371 % | 3775.538 | 3764.209 | −0 % |
| `ring_write` | 25 | 366 | +1367 % | 3935.373 | 4022.296 | +2 % |
| `histogram_bins` | 25 | 366 | +1364 % | 3758.762 | 4093.834 | +9 % |
| `prefix_scan` | 25 | 366 | +1347 % | 586.718 | 642.139 | +9 % |
| `binary_search` | 25 | 365 | +1361 % | 4269.351 | 4406.754 | +3 % |
| `sort_window` | 25 | 366 | +1348 % | 3089.145 | 3220.925 | +4 % |
| `bloom_filter` | 25 | 366 | +1355 % | 983.038 | 1045.757 | +6 % |
| `hash_join` | 27 | 368 | +1264 % | 2953.530 | 3131.456 | +6 % |
| `sieve` | 25 | 366 | +1365 % | 3928.693 | 3978.341 | +1 % |
| `fib` | 25 | 365 | +1371 % | 2873.952 | 2793.430 | −3 % |
| `collatz` | 25 | 365 | +1372 % | 1968.200 | 2076.419 | +5 % |
| `matmul` | 25 | 366 | +1350 % | 1251.613 | 1303.171 | +4 % |
| `json_parse` | 45 | 380 | +747 % | 695.945 | 782.076 | +12 % |
| `nbody` | 27 | 367 | +1273 % | 2392.849 | 2507.440 | +5 % |
| `safe_record_array` | 34 | 369 | +984 % | 6361.288 | 6340.972 | −0 % |
| `payload_state_machine` | 31 | 370 | +1075 % | 13150.410 | 13302.623 | +1 % |
| `captured_closure_queue` | 36 | 371 | +919 % | 12934.099 | 13187.737 | +2 % |
| `dynamic_method_mix` | 35 | 370 | +949 % | 14365.626 | 14182.536 | −1 % |
| `csv_table_pipeline` | 68 | 391 | +477 % | 10716.295 | 10696.423 | −0 % |
| `chacha20` | 39 | 446 | +1041 % | 2314.448 | 2420.005 | +5 % |
| `poly1305` | 33 | 407 | +1128 % | 6079.954 | 6078.294 | −0 % |
| `blake2b` | 41 | 378 | +822 % | 3423.298 | 3482.323 | +2 % |
| `sha512` | 39 | 377 | +859 % | 3883.239 | 4219.289 | +9 % |
| `x25519` | 46 | 398 | +756 % | 15868.164 | 15731.071 | −1 % |

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
| _(floor: empty program)_ | _4.923_ | _55.264_ | _61.631_ | _24.199_ | _26.554_ | _49.966_ | _74.120_ |
| `lcg` | 4.981 | 63.677 | 45.524 | 26.061 | 27.160 | 53.390 | 59.728 |
| `packet_classifier` | 5.396 | 64.978 | 44.351 | 25.913 | 24.806 | 50.546 | 58.378 |
| `ring_write` | 12.756 | 78.537 | 66.440 | 28.410 | 28.546 | 60.900 | 66.871 |
| `histogram_bins` | 11.658 | 76.385 | 60.347 | 28.355 | 27.720 | 59.075 | 66.414 |
| `prefix_scan` | 11.894 | 75.467 | 56.976 | 26.874 | 24.463 | 53.797 | 75.033 |
| `binary_search` | 11.868 | 76.665 | 58.852 | 27.241 | 26.365 | 59.890 | 64.398 |
| `sort_window` | 11.606 | 77.920 | 70.022 | 28.570 | 26.032 | 61.938 | 80.073 |
| `bloom_filter` | 11.914 | 74.003 | 64.735 | 28.184 | 28.861 | 56.955 | 66.729 |
| `hash_join` | 14.306 | 123.871 | 97.871 | 50.682 | 25.771 | 82.152 | 86.429 |
| `sieve` | 11.763 | 77.759 | 67.330 | 34.991 | 26.108 | 70.546 | 69.338 |
| `fib` | 5.274 | 60.515 | 45.078 | 23.513 | 27.607 | 51.610 | 58.461 |
| `collatz` | 5.396 | 63.927 | 48.307 | 26.545 | 24.381 | 54.446 | 61.771 |
| `matmul` | 11.384 | 74.875 | 60.923 | 29.848 | 27.775 | 65.616 | 75.353 |
| `json_parse` | 35.472 | 233.419 | 222.958 | 50.162 | 26.641 | 132.009 | 126.396 |
| `nbody` | 12.075 | 76.588 | 69.838 | 37.495 | 24.526 | 67.650 | 74.460 |
| `safe_record_array` | 13.678 | 130.500 | 84.391 | 30.833 | 28.946 | 71.612 | 77.329 |
| `payload_state_machine` | 19.792 | 115.284 | 106.861 | 32.690 | 24.521 | 72.510 | 75.418 |
| `captured_closure_queue` | 16.517 | 180.297 | 110.146 | 42.066 | 27.204 | 106.347 | 97.202 |
| `dynamic_method_mix` | 15.344 | 168.960 | 105.742 | 34.098 | 24.729 | 87.130 | 93.658 |
| `csv_table_pipeline` | 57.181 | 407.019 | 362.938 | 103.701 | 25.904 | 187.161 | 189.727 |
| `chacha20` | 43.405 | 366.151 | 546.594 | 45.659 | 26.210 | 84.640 | 88.990 |
| `poly1305` | 40.331 | 265.082 | 263.471 | 46.970 | 26.286 | 86.809 | 101.763 |
| `blake2b` | 28.132 | 245.352 | 176.855 | 42.814 | 25.751 | 90.355 | 95.128 |
| `sha512` | 24.832 | 242.204 | 168.181 | 38.278 | 26.372 | 82.190 | 90.755 |
| `x25519` | 34.387 | 909.982 | 588.716 | 396.608 | 28.676 | 451.455 | 459.650 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `5013499978263536346` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `3449592071` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `6773938213699575018` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `3532155438` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `1287806229` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `3557324949` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `5384552423` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `235255863` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `0` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `66457900` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `922746500` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `685` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `39321553` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `2000` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595259045357180835` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `safe_record_array` | `2141196011152232362` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `payload_state_machine` | `5505773189712423741` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `captured_closure_queue` | `6380078867738382757` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `dynamic_method_mix` | `4212374204251174567` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `csv_table_pipeline` | `7164823160966689843` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `chacha20` | `8394054855872980010` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `8248528072407566179` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `1931941996404473087` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sha512` | `6821780943419649564` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `x25519` | `293414653143968088` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
