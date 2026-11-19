# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-19T11:59:26Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-x300.json`](results/wasm-x300.json).

**Workload ×300.** Every benchmark below does 300 times its published
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
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `e15ed57f998cbc8deb360fef791281fe77b5e588` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44499444051 |
| NURL | `v0.92.1-82-ge15ed57f` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.9), built from this repo |
| C → wasm | `zig 0.17.1 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.5 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Workload scale | ×300 — every benchmark's work multiplied by 300 before compilation |
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
| _(floor: empty program)_ | _2.967_ | _11.306_ | _3.8_ | _3.028_ | _7.494_ | _2.5_ | _3.131_ | _30.242_ | _9.7_ |
| `lcg` | 9820.496 | 9837.802 | 1.0 | 9814.424 | 9850.838 | 1.0 | 9817.242 | 9846.681 | 1.0 |
| `packet_classifier` | 14320.884 | 13317.138 | 0.9 | 14320.789 | 13320.104 | 0.9 | 14326.651 | 13330.185 | 0.9 |
| `ring_write` | 10636.128 | 13123.193 | 1.2 | 10636.353 | 13134.921 | 1.2 | 10639.418 | 13124.245 | 1.2 |
| `histogram_bins` | 9947.126 | 12729.308 | 1.3 | 9936.621 | 11867.890 | 1.2 | 9937.615 | 12570.484 | 1.3 |
| `prefix_scan` | 5289.196 | 2239.307 | 0.4 | 5307.193 | 2178.220 | 0.4 | 5292.629 | 2244.302 | 0.4 |
| `binary_search` | 7277.641 | 14230.942 | 2.0 | 7404.947 | 15078.157 | 2.0 | 10681.854 | 14773.374 | 1.4 |
| `sort_window` | 6715.278 | 9483.811 | 1.4 | 15460.939 | 7937.552 | 0.5 | 6548.046 | 7747.595 | 1.2 |
| `bloom_filter` | 3609.019 | 3978.633 | 1.1 | 4336.214 | 4123.996 | 1.0 | 4335.986 | 3852.298 | 0.9 |
| `hash_join` | 5762.898 | 9482.602 | 1.6 | 6677.864 | 8894.524 | 1.3 | 6700.820 | 9413.440 | 1.4 |
| `sieve` | 4099.804 | 4852.063 | 1.2 | 4075.975 | 6086.712 | 1.5 | 4094.668 | 5993.630 | 1.5 |
| `fib` | 6066.388 | 10088.810 | 1.7 | 6356.078 | 9570.681 | 1.5 | 7303.425 | 9325.365 | 1.3 |
| `collatz` | 4211.393 | 6882.429 | 1.6 | 4203.684 | 6890.263 | 1.6 | 4205.940 | 6889.990 | 1.6 |
| `matmul` | 10057.471 | 8898.751 | 0.9 | 10202.108 | 7231.220 | 0.7 | 10042.210 | 7199.309 | 0.7 |
| `json_parse` | 906.308 | 2542.863 | 2.8 | 2284.959 | 1362.050 | 0.6 | 3451.423 | 2611.550 | 0.8 |
| `nbody` | 10304.489 | 10138.851 | 1.0 | 11166.627 | 9996.880 | 0.9 | 9753.211 | 9924.389 | 1.0 |
| `safe_record_array` | 14470.281 | 18903.229 | 1.3 | 13632.982 | 17223.400 | 1.3 | 16413.807 | 16925.967 | 1.0 |
| `payload_state_machine` | 19396.981 | 45647.215 | 2.4 | 18345.631 | 26645.155 | 1.5 | 18644.160 | 26312.310 | 1.4 |
| `captured_closure_queue` | 27096.870 | 40922.369 | 1.5 | 21141.220 | 36262.807 | 1.7 | 25195.913 | 38359.454 | 1.5 |
| `dynamic_method_mix` | 29797.845 | 51873.355 | 1.7 | 31856.755 | 47415.396 | 1.5 | 29835.497 | 49734.754 | 1.7 |
| `csv_table_pipeline` | 15419.540 | 31625.609 | 2.1 | 23150.135 | 28301.491 | 1.2 | 14469.627 | 23529.662 | 1.6 |
| `chacha20` | 965.444 | 9244.018 | 9.6 | 9284.338 | 10752.807 | 1.2 | 10163.962 | 10652.632 | 1.0 |
| `poly1305` | 2803.005 | 26332.156 | 9.4 | 5115.513 | 25602.009 | 5.0 | 5102.778 | 31373.441 | 6.1 |
| `blake2b` | 10613.768 | 11293.232 | 1.1 | 16670.535 | 18694.956 | 1.1 | 17720.840 | 22747.439 | 1.3 |
| `sha512` | 11130.647 | 13587.533 | 1.2 | 11936.520 | 14056.982 | 1.2 | 12153.565 | 14246.703 | 1.2 |
| `x25519` | 7974.001 | 62963.985 | 7.9 | 14363.042 | 80385.543 | 5.6 | 13318.734 | 104281.474 | 7.8 |

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
| `packet_classifier` | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.2 |
| `histogram_bins` | 1.3 | 1.3 | 1.2 | 1.3 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 2.0 | 2.0 | 2.0 | 1.4 |
| `sort_window` | 1.4 | 1.6 | 0.5 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 0.9 | 0.9 |
| `hash_join` | 1.6 | 1.7 | 1.3 | 1.4 |
| `sieve` | 1.2 | 1.2 | 1.5 | 1.5 |
| `fib` | 1.7 | 1.7 | 1.5 | 1.3 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.7 | 0.7 |
| `json_parse` | 2.8 | 2.8 | 0.6 | 0.7 |
| `nbody` | 1.0 | 1.0 | 0.9 | 1.0 |
| `safe_record_array` | 1.3 | 1.3 | 1.3 | 1.0 |
| `payload_state_machine` | 2.4 | 2.3 | 1.5 | 1.4 |
| `captured_closure_queue` | 1.5 | 1.5 | 1.7 | 1.5 |
| `dynamic_method_mix` | 1.7 | 1.7 | 1.5 | 1.7 |
| `csv_table_pipeline` | 2.1 | 2.1 | 1.2 | 1.6 |
| `chacha20` | 9.6 | 9.6 | 1.2 | 1.0 |
| `poly1305` | 9.4 | 9.4 | 5.0 | 6.1 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 7.9 | 7.9 | 5.6 | 7.8 |

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
| _(floor: empty program)_ | _11.306_ | _4.891_ | _7.494_ | _**4.754**_ | _30.242_ | _5.781_ |
| `lcg` | 9837.802 | 9823.840 | 9850.838 | **9823.192** | 9846.681 | 9823.659 |
| `packet_classifier` | 13317.138 | 12277.494 | 13320.104 | **12276.802** | 13330.185 | 12291.042 |
| `ring_write` | 13123.193 | 11470.425 | 13134.921 | **11460.033** | 13124.245 | 11463.582 |
| `histogram_bins` | 12729.308 | **10213.024** | 11867.890 | 10466.636 | 12570.484 | 10215.218 |
| `prefix_scan` | 2239.307 | **1650.307** | 2178.220 | 2173.859 | 2244.302 | 1657.034 |
| `binary_search` | 14230.942 | **11888.623** | 15078.157 | 11979.575 | 14773.374 | 13048.958 |
| `sort_window` | 9483.811 | 10347.080 | 7937.552 | 9217.154 | **7747.595** | 8875.110 |
| `bloom_filter` | 3978.633 | 3272.539 | 4123.996 | **3234.595** | 3852.298 | 3252.778 |
| `hash_join` | 9482.602 | **8786.562** | 8894.524 | 8909.749 | 9413.440 | 8870.387 |
| `sieve` | 4852.063 | 5829.914 | 6086.712 | 5980.654 | 5993.630 | **4710.745** |
| `fib` | 10088.810 | 7045.033 | 9570.681 | 7456.487 | 9325.365 | **6837.069** |
| `collatz` | 6882.429 | **6838.907** | 6890.263 | 6840.650 | 6889.990 | 6846.839 |
| `matmul` | 8898.751 | 7756.787 | 7231.220 | 5719.192 | 7199.309 | **5499.658** |
| `json_parse` | 2542.863 | 2897.273 | 1362.050 | **1217.350** | 2611.550 | 2603.938 |
| `nbody` | 10138.851 | 11748.777 | 9996.880 | 10014.389 | **9924.389** | 10747.505 |
| `safe_record_array` | 18903.229 | 19756.866 | 17223.400 | 18129.178 | **16925.967** | 18048.339 |
| `payload_state_machine` | 45647.215 | 49434.235 | 26645.155 | **26166.465** | 26312.310 | 26440.089 |
| `captured_closure_queue` | 40922.369 | 48155.607 | **36262.807** | 37026.549 | 38359.454 | 43356.279 |
| `dynamic_method_mix` | 51873.355 | 57306.678 | **47415.396** | 58286.568 | 49734.754 | 60932.859 |
| `csv_table_pipeline` | 31625.609 | 30656.348 | 28301.491 | 27427.988 | 23529.662 | **23180.905** |
| `chacha20` | 9244.018 | **9224.545** | 10752.807 | 11476.190 | 10652.632 | 11691.110 |
| `poly1305` | 26332.156 | 15190.949 | 25602.009 | **13521.928** | 31373.441 | 13984.945 |
| `blake2b` | **11293.232** | 12969.037 | 18694.956 | 20327.729 | 22747.439 | 24599.388 |
| `sha512` | 13587.533 | **13176.996** | 14056.982 | 14655.265 | 14246.703 | 15296.787 |
| `x25519` | 62963.985 | 35995.988 | 80385.543 | **35917.205** | 104281.474 | 36057.759 |

`nwasm` is faster than the reference runtime on 16 of 25 NURL modules,
16 of 25 C modules and 16 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.891_ | _0.4_ | _1.6_ | _0.6_ | _0.2_ |
| `lcg` | 9823.840 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 12277.494 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 11470.425 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 10213.024 | 0.8 | 1.0 | 0.9 | 0.8 |
| `prefix_scan` | 1650.307 | 0.7 | 0.3 | 1.0 | 0.7 |
| `binary_search` | 11888.623 | 0.8 | 1.6 | 0.8 | 0.9 |
| `sort_window` | 10347.080 | 1.1 | 1.5 | 1.2 | 1.1 |
| `bloom_filter` | 3272.539 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 8786.562 | 0.9 | 1.5 | 1.0 | 0.9 |
| `sieve` | 5829.914 | 1.2 | 1.4 | 1.0 | 0.8 |
| `fib` | 7045.033 | 0.7 | 1.2 | 0.8 | 0.7 |
| `collatz` | 6838.907 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 7756.787 | 0.9 | 0.8 | 0.8 | 0.8 |
| `json_parse` | 2897.273 | 1.1 | 3.2 | 0.9 | 1.0 |
| `nbody` | 11748.777 | 1.2 | 1.1 | 1.0 | 1.1 |
| `safe_record_array` | 19756.866 | 1.0 | 1.4 | 1.1 | 1.1 |
| `payload_state_machine` | 49434.235 | 1.1 | 2.5 | 1.0 | 1.0 |
| `captured_closure_queue` | 48155.607 | 1.2 | 1.8 | 1.0 | 1.1 |
| `dynamic_method_mix` | 57306.678 | 1.1 | 1.9 | 1.2 | 1.2 |
| `csv_table_pipeline` | 30656.348 | 1.0 | 2.0 | 1.0 | 1.0 |
| `chacha20` | 9224.545 | 1.0 | 9.6 | 1.1 | 1.1 |
| `poly1305` | 15190.949 | 0.6 | 5.4 | 0.5 | 0.4 |
| `blake2b` | 12969.037 | 1.1 | 1.2 | 1.1 | 1.1 |
| `sha512` | 13176.996 | 1.0 | 1.2 | 1.0 | 1.1 |
| `x25519` | 35995.988 | 0.6 | 4.5 | 0.4 | 0.3 |

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
| `matmul` | 12 | 25 | 7 | 931 | 4389 | 2138 |
| `json_parse` | 35 | 44 | 10 | 1021 | 4402 | 2168 |
| `nbody` | 13 | 27 | 8 | 934 | 4389 | 2138 |
| `safe_record_array` | 27 | 34 | 7 | 933 | 4389 | 2139 |
| `payload_state_machine` | 21 | 31 | 7 | 936 | 4390 | 2139 |
| `captured_closure_queue` | 34 | 36 | 9 | 939 | 4395 | 2142 |
| `dynamic_method_mix` | 33 | 35 | 9 | 937 | 4393 | 2141 |
| `csv_table_pipeline` | 64 | 68 | 17 | 965 | 4400 | 2148 |
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
| _(floor: empty program)_ | _4_ | _366_ | _+9314 %_ | _11.306_ | _132.519_ | _+1072 %_ |
| `lcg` | 25 | 366 | +1372 % | 9837.802 | 9956.956 | +1 % |
| `packet_classifier` | 25 | 366 | +1374 % | 13317.138 | 13420.885 | +1 % |
| `ring_write` | 25 | 366 | +1370 % | 13123.193 | 13217.042 | +1 % |
| `histogram_bins` | 25 | 366 | +1367 % | 12729.308 | 12828.283 | +1 % |
| `prefix_scan` | 25 | 366 | +1350 % | 2239.307 | 2342.797 | +5 % |
| `binary_search` | 25 | 366 | +1364 % | 14230.942 | 14328.653 | +1 % |
| `sort_window` | 25 | 367 | +1351 % | 9483.811 | 10623.546 | +12 % |
| `bloom_filter` | 25 | 367 | +1358 % | 3978.633 | 4063.666 | +2 % |
| `hash_join` | 27 | 369 | +1266 % | 9482.602 | 9924.018 | +5 % |
| `sieve` | 25 | 366 | +1368 % | 4852.063 | 4956.471 | +2 % |
| `fib` | 25 | 366 | +1374 % | 10088.810 | 10144.245 | +1 % |
| `collatz` | 25 | 366 | +1375 % | 6882.429 | 6986.304 | +2 % |
| `matmul` | 25 | 366 | +1353 % | 8898.751 | 8897.053 | −0 % |
| `json_parse` | 44 | 380 | +755 % | 2542.863 | 2644.812 | +4 % |
| `nbody` | 27 | 368 | +1276 % | 10138.851 | 10233.528 | +1 % |
| `safe_record_array` | 34 | 369 | +997 % | 18903.229 | 19311.742 | +2 % |
| `payload_state_machine` | 31 | 370 | +1082 % | 45647.215 | 45593.026 | −0 % |
| `captured_closure_queue` | 36 | 371 | +920 % | 40922.369 | 42002.041 | +3 % |
| `dynamic_method_mix` | 35 | 371 | +950 % | 51873.355 | 51562.592 | −1 % |
| `csv_table_pipeline` | 68 | 391 | +478 % | 31625.609 | 31787.083 | +1 % |
| `chacha20` | 37 | 442 | +1091 % | 9244.018 | 9402.735 | +2 % |
| `poly1305` | 33 | 407 | +1145 % | 26332.156 | 26417.489 | +0 % |
| `blake2b` | 40 | 378 | +841 % | 11293.232 | 11403.681 | +1 % |
| `sha512` | 39 | 377 | +869 % | 13587.533 | 13672.849 | +1 % |
| `x25519` | 46 | 398 | +764 % | 62963.985 | 62852.790 | −0 % |

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
| _(floor: empty program)_ | _6.219_ | _66.403_ | _60.989_ | _29.483_ | _37.578_ | _49.804_ | _61.741_ |
| `lcg` | 6.651 | 74.702 | 71.688 | 34.061 | 37.808 | 53.960 | 67.481 |
| `packet_classifier` | 6.564 | 75.756 | 64.947 | 35.070 | 38.608 | 55.212 | 67.227 |
| `ring_write` | 12.099 | 84.588 | 76.760 | 36.230 | 37.980 | 56.406 | 67.906 |
| `histogram_bins` | 12.279 | 84.762 | 78.432 | 36.296 | 37.941 | 56.977 | 68.104 |
| `prefix_scan` | 12.183 | 86.654 | 77.990 | 36.095 | 51.787 | 57.982 | 70.837 |
| `binary_search` | 12.719 | 89.764 | 80.733 | 37.611 | 39.136 | 61.809 | 73.771 |
| `sort_window` | 12.521 | 88.545 | 82.471 | 37.672 | 38.866 | 63.411 | 73.955 |
| `bloom_filter` | 12.800 | 87.353 | 82.390 | 37.651 | 37.474 | 59.384 | 70.618 |
| `hash_join` | 15.510 | 138.901 | 125.375 | 57.043 | 37.477 | 85.789 | 98.138 |
| `sieve` | 12.421 | 87.520 | 82.544 | 40.914 | 38.495 | 66.273 | 76.432 |
| `fib` | 6.787 | 77.283 | 64.764 | 34.804 | 37.666 | 55.540 | 68.036 |
| `collatz` | 6.766 | 78.073 | 68.261 | 35.143 | 39.023 | 56.381 | 68.309 |
| `matmul` | 12.711 | 90.307 | 81.145 | 41.373 | 37.376 | 71.988 | 81.591 |
| `json_parse` | 39.036 | 267.046 | 269.235 | 59.530 | 37.977 | 134.692 | 123.323 |
| `nbody` | 13.788 | 92.798 | 93.936 | 48.736 | 37.778 | 72.749 | 84.319 |
| `safe_record_array` | 15.028 | 174.300 | 110.508 | 41.078 | 37.160 | 74.333 | 84.345 |
| `payload_state_machine` | 23.029 | 154.423 | 133.015 | 43.626 | 37.451 | 77.068 | 85.478 |
| `captured_closure_queue` | 18.331 | 213.078 | 138.053 | 47.242 | 37.542 | 98.057 | 99.383 |
| `dynamic_method_mix` | 17.855 | 210.535 | 137.310 | 46.006 | 37.406 | 90.785 | 97.414 |
| `csv_table_pipeline` | 70.155 | 503.535 | 451.099 | 121.723 | 39.453 | 197.327 | 203.239 |
| `chacha20` | 55.592 | 428.856 | 640.147 | 55.179 | 38.106 | 89.182 | 97.782 |
| `poly1305` | 44.926 | 303.356 | 324.080 | 60.251 | 37.623 | 94.258 | 105.906 |
| `blake2b` | 29.908 | 275.681 | 213.648 | 54.960 | 37.468 | 99.252 | 106.743 |
| `sha512` | 28.485 | 294.151 | 206.948 | 49.504 | 37.995 | 87.611 | 96.651 |
| `x25519` | 42.007 | 1026.208 | 682.422 | 480.665 | 39.777 | 504.824 | 532.177 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-1226497962176115656` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `2462986371` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `5626421774843711691` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `7370756466` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `3281681685` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `2207568789` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `5465279453` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `705779661` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `0` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `199373700` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `2768239500` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `704` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `117964714` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `6000` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595259552488757381` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `safe_record_array` | `5653786785231687554` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `payload_state_machine` | `2032895883230250981` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `captured_closure_queue` | `5692881218510219471` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `dynamic_method_mix` | `8717292098921376902` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `csv_table_pipeline` | `358538211080478995` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `chacha20` | `6829235544412143774` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `3185392352052989010` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `2447936398681434931` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sha512` | `5721417887030972397` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `x25519` | `6447182163740088706` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
