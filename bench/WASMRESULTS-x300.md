# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-27T00:08:15Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `986339c9f1d1a3b3cd6d7ed4a5b4d1191a490e30` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45901351080 |
| NURL | `v0.95.0-8-g986339c9f` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.9), built from this repo |
| C → wasm | `zig 0.17.1 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.6 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _2.941_ | _10.280_ | _3.5_ | _2.986_ | _8.193_ | _2.7_ | _3.101_ | _29.907_ | _9.6_ |
| `lcg` | 9820.836 | 9853.893 | 1.0 | 9819.103 | 9847.669 | 1.0 | 9830.834 | 9857.999 | 1.0 |
| `packet_classifier` | 14322.048 | 13329.903 | 0.9 | 14319.250 | 13322.340 | 0.9 | 14335.938 | 13323.961 | 0.9 |
| `ring_write` | 10635.321 | 13125.223 | 1.2 | 10676.699 | 13113.582 | 1.2 | 10650.185 | 13117.064 | 1.2 |
| `histogram_bins` | 9940.908 | 12743.023 | 1.3 | 9933.812 | 11878.410 | 1.2 | 9940.638 | 12544.155 | 1.3 |
| `prefix_scan` | 5295.519 | 2236.785 | 0.4 | 5297.059 | 2185.799 | 0.4 | 5289.048 | 2245.957 | 0.4 |
| `binary_search` | 7380.936 | 14233.628 | 1.9 | 7408.094 | 15046.139 | 2.0 | 10701.681 | 14797.883 | 1.4 |
| `sort_window` | 6716.237 | 9482.975 | 1.4 | 15483.693 | 7940.340 | 0.5 | 6549.550 | 7776.254 | 1.2 |
| `bloom_filter` | 3622.534 | 3958.552 | 1.1 | 4338.296 | 4113.975 | 0.9 | 4336.421 | 3870.727 | 0.9 |
| `hash_join` | 5754.748 | 9462.775 | 1.6 | 6673.564 | 8901.034 | 1.3 | 6723.837 | 9454.444 | 1.4 |
| `sieve` | 4088.558 | 4862.144 | 1.2 | 4084.523 | 6081.963 | 1.5 | 4101.770 | 6032.745 | 1.5 |
| `fib` | 6069.094 | 10066.205 | 1.7 | 6368.199 | 9584.529 | 1.5 | 7299.896 | 9324.591 | 1.3 |
| `collatz` | 4203.456 | 6877.283 | 1.6 | 4204.768 | 6900.997 | 1.6 | 4211.297 | 6897.835 | 1.6 |
| `matmul` | 10192.270 | 8774.254 | 0.9 | 9927.053 | 7205.854 | 0.7 | 10084.965 | 7142.736 | 0.7 |
| `json_parse` | 858.265 | 2504.524 | 2.9 | 2298.911 | 1367.119 | 0.6 | 3525.554 | 2610.951 | 0.7 |
| `nbody` | 10313.231 | 10164.206 | 1.0 | 11175.350 | 10007.222 | 0.9 | 9764.374 | 9923.227 | 1.0 |
| `safe_record_array` | 14292.834 | 18823.467 | 1.3 | 13627.288 | 17337.703 | 1.3 | 16416.490 | 16908.980 | 1.0 |
| `payload_state_machine` | 19061.827 | 44230.732 | 2.3 | 18324.605 | 26631.537 | 1.5 | 18654.179 | 26325.242 | 1.4 |
| `captured_closure_queue` | 26686.486 | 40320.564 | 1.5 | 21156.686 | 36349.847 | 1.7 | 25207.685 | 38627.940 | 1.5 |
| `dynamic_method_mix` | 37527.378 | 51946.476 | 1.4 | 31776.241 | 47363.626 | 1.5 | 29545.273 | 49327.947 | 1.7 |
| `csv_table_pipeline` | 15363.545 | 31712.126 | 2.1 | 23231.250 | 28289.995 | 1.2 | 14428.878 | 23529.794 | 1.6 |
| `chacha20` | 965.380 | 9254.142 | 9.6 | 9311.470 | 10783.135 | 1.2 | 10125.870 | 10698.226 | 1.1 |
| `poly1305` | 2792.461 | 26123.686 | 9.4 | 5088.567 | 25656.822 | 5.0 | 5101.919 | 31382.699 | 6.2 |
| `blake2b` | 10575.138 | 11775.939 | 1.1 | 16635.821 | 18706.132 | 1.1 | 17643.231 | 22707.777 | 1.3 |
| `sha512` | 11144.469 | 13561.461 | 1.2 | 11938.514 | 14040.221 | 1.2 | 12127.103 | 14273.880 | 1.2 |
| `x25519` | 7989.322 | 65158.426 | 8.2 | 13954.416 | 80341.758 | 5.8 | 13228.859 | 104035.571 | 7.9 |

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
| `binary_search` | 1.9 | 1.9 | 2.0 | 1.4 |
| `sort_window` | 1.4 | 1.6 | 0.5 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 0.9 | 0.9 |
| `hash_join` | 1.6 | 1.7 | 1.3 | 1.4 |
| `sieve` | 1.2 | 1.2 | 1.5 | 1.5 |
| `fib` | 1.7 | 1.7 | 1.5 | 1.3 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.7 | 0.7 |
| `json_parse` | 2.9 | 2.9 | 0.6 | 0.7 |
| `nbody` | 1.0 | 1.0 | 0.9 | 1.0 |
| `safe_record_array` | 1.3 | 1.3 | 1.3 | 1.0 |
| `payload_state_machine` | 2.3 | 2.4 | 1.5 | 1.4 |
| `captured_closure_queue` | 1.5 | 1.6 | 1.7 | 1.5 |
| `dynamic_method_mix` | 1.4 | 1.4 | 1.5 | 1.7 |
| `csv_table_pipeline` | 2.1 | 2.1 | 1.2 | 1.6 |
| `chacha20` | 9.6 | 9.6 | 1.2 | 1.1 |
| `poly1305` | 9.4 | 9.4 | 5.0 | 6.1 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 8.2 | 7.9 | 5.8 | 7.9 |

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
| _(floor: empty program)_ | _10.280_ | _4.593_ | _8.193_ | _**4.220**_ | _29.907_ | _5.621_ |
| `lcg` | 9853.893 | **9828.839** | 9847.669 | 9835.185 | 9857.999 | 9830.784 |
| `packet_classifier` | 13329.903 | 12288.803 | 13322.340 | 12285.532 | 13323.961 | **12282.902** |
| `ring_write` | 13125.223 | 11465.891 | 13113.582 | 11479.523 | 13117.064 | **11465.748** |
| `histogram_bins` | 12743.023 | **10221.535** | 11878.410 | 10450.226 | 12544.155 | 10222.004 |
| `prefix_scan` | 2236.785 | **1648.481** | 2185.799 | 2174.436 | 2245.957 | 1653.033 |
| `binary_search` | 14233.628 | **11902.384** | 15046.139 | 11983.724 | 14797.883 | 13099.350 |
| `sort_window` | 9482.975 | 10353.337 | 7940.340 | 9253.825 | **7776.254** | 8893.169 |
| `bloom_filter` | 3958.552 | 3272.078 | 4113.975 | **3239.892** | 3870.727 | 3247.936 |
| `hash_join` | 9462.775 | **8778.292** | 8901.034 | 8902.634 | 9454.444 | 8873.653 |
| `sieve` | 4862.144 | 5864.376 | 6081.963 | 5978.207 | 6032.745 | **4660.105** |
| `fib` | 10066.205 | 7066.033 | 9584.529 | 7064.424 | 9324.591 | **6873.315** |
| `collatz` | 6877.283 | 6851.269 | 6900.997 | 6851.566 | 6897.835 | **6848.166** |
| `matmul` | 8774.254 | 7791.883 | 7205.854 | 5913.603 | 7142.736 | **5772.753** |
| `json_parse` | 2504.524 | 2647.728 | 1367.119 | **1218.902** | 2610.951 | 2594.020 |
| `nbody` | 10164.206 | 11746.080 | 10007.222 | 10019.174 | **9923.227** | 10756.769 |
| `safe_record_array` | 18823.467 | 19156.514 | 17337.703 | 18028.452 | **16908.980** | 18243.041 |
| `payload_state_machine` | 44230.732 | 45645.692 | 26631.537 | **26022.840** | 26325.242 | 26464.993 |
| `captured_closure_queue` | 40320.564 | 47891.798 | **36349.847** | 37094.506 | 38627.940 | 43349.256 |
| `dynamic_method_mix` | 51946.476 | 59557.633 | **47363.626** | 58993.383 | 49327.947 | 61644.675 |
| `csv_table_pipeline` | 31712.126 | 30386.887 | 28289.995 | 27551.608 | 23529.794 | **23104.259** |
| `chacha20` | **9254.142** | 9297.088 | 10783.135 | 11439.878 | 10698.226 | 11682.112 |
| `poly1305` | 26123.686 | 16931.152 | 25656.822 | **13520.407** | 31382.699 | 13990.471 |
| `blake2b` | **11775.939** | 12993.774 | 18706.132 | 20313.237 | 22707.777 | 24569.392 |
| `sha512` | 13561.461 | **13207.251** | 14040.221 | 14708.310 | 14273.880 | 15288.211 |
| `x25519` | 65158.426 | 36113.482 | 80341.758 | **35961.883** | 104035.571 | 35971.267 |

`nwasm` is faster than the reference runtime on 15 of 25 NURL modules,
16 of 25 C modules and 16 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.593_ | _0.4_ | _1.6_ | _0.5_ | _0.2_ |
| `lcg` | 9828.839 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 12288.803 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 11465.891 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 10221.535 | 0.8 | 1.0 | 0.9 | 0.8 |
| `prefix_scan` | 1648.481 | 0.7 | 0.3 | 1.0 | 0.7 |
| `binary_search` | 11902.384 | 0.8 | 1.6 | 0.8 | 0.9 |
| `sort_window` | 10353.337 | 1.1 | 1.5 | 1.2 | 1.1 |
| `bloom_filter` | 3272.078 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 8778.292 | 0.9 | 1.5 | 1.0 | 0.9 |
| `sieve` | 5864.376 | 1.2 | 1.4 | 1.0 | 0.8 |
| `fib` | 7066.033 | 0.7 | 1.2 | 0.7 | 0.7 |
| `collatz` | 6851.269 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 7791.883 | 0.9 | 0.8 | 0.8 | 0.8 |
| `json_parse` | 2647.728 | 1.1 | 3.1 | 0.9 | 1.0 |
| `nbody` | 11746.080 | 1.2 | 1.1 | 1.0 | 1.1 |
| `safe_record_array` | 19156.514 | 1.0 | 1.3 | 1.0 | 1.1 |
| `payload_state_machine` | 45645.692 | 1.0 | 2.4 | 1.0 | 1.0 |
| `captured_closure_queue` | 47891.798 | 1.2 | 1.8 | 1.0 | 1.1 |
| `dynamic_method_mix` | 59557.633 | 1.1 | 1.6 | 1.2 | 1.2 |
| `csv_table_pipeline` | 30386.887 | 1.0 | 2.0 | 1.0 | 1.0 |
| `chacha20` | 9297.088 | 1.0 | 9.6 | 1.1 | 1.1 |
| `poly1305` | 16931.152 | 0.6 | 6.1 | 0.5 | 0.4 |
| `blake2b` | 12993.774 | 1.1 | 1.2 | 1.1 | 1.1 |
| `sha512` | 13207.251 | 1.0 | 1.2 | 1.0 | 1.1 |
| `x25519` | 36113.482 | 0.6 | 4.5 | 0.4 | 0.3 |

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
| `json_parse` | 36 | 44 | 10 | 1021 | 4402 | 2168 |
| `nbody` | 13 | 27 | 8 | 934 | 4389 | 2138 |
| `safe_record_array` | 27 | 34 | 7 | 933 | 4389 | 2139 |
| `payload_state_machine` | 21 | 31 | 7 | 936 | 4390 | 2139 |
| `captured_closure_queue` | 34 | 36 | 9 | 939 | 4395 | 2142 |
| `dynamic_method_mix` | 33 | 35 | 9 | 937 | 4393 | 2141 |
| `csv_table_pipeline` | 63 | 66 | 17 | 965 | 4400 | 2148 |
| `chacha20` | 40 | 37 | 7 | 937 | 4389 | 2138 |
| `poly1305` | 33 | 33 | 7 | 935 | 4389 | 2138 |
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
| _(floor: empty program)_ | _4_ | _366_ | _+9314 %_ | _10.280_ | _127.989_ | _+1145 %_ |
| `lcg` | 25 | 366 | +1372 % | 9853.893 | 9946.584 | +1 % |
| `packet_classifier` | 25 | 366 | +1374 % | 13329.903 | 13450.837 | +1 % |
| `ring_write` | 25 | 366 | +1370 % | 13125.223 | 13223.162 | +1 % |
| `histogram_bins` | 25 | 366 | +1367 % | 12743.023 | 12822.686 | +1 % |
| `prefix_scan` | 25 | 366 | +1350 % | 2236.785 | 2363.299 | +6 % |
| `binary_search` | 25 | 366 | +1364 % | 14233.628 | 14342.143 | +1 % |
| `sort_window` | 25 | 367 | +1351 % | 9482.975 | 10639.919 | +12 % |
| `bloom_filter` | 25 | 367 | +1358 % | 3958.552 | 4075.791 | +3 % |
| `hash_join` | 27 | 369 | +1266 % | 9462.775 | 9906.712 | +5 % |
| `sieve` | 25 | 366 | +1368 % | 4862.144 | 4963.873 | +2 % |
| `fib` | 25 | 366 | +1374 % | 10066.205 | 10174.183 | +1 % |
| `collatz` | 25 | 366 | +1375 % | 6877.283 | 6986.182 | +2 % |
| `matmul` | 25 | 366 | +1353 % | 8774.254 | 8907.414 | +2 % |
| `json_parse` | 44 | 380 | +758 % | 2504.524 | 2617.900 | +5 % |
| `nbody` | 27 | 368 | +1276 % | 10164.206 | 10255.679 | +1 % |
| `safe_record_array` | 34 | 369 | +999 % | 18823.467 | 18712.659 | −1 % |
| `payload_state_machine` | 31 | 369 | +1086 % | 44230.732 | 45086.822 | +2 % |
| `captured_closure_queue` | 36 | 371 | +924 % | 40320.564 | 41884.358 | +4 % |
| `dynamic_method_mix` | 35 | 371 | +955 % | 51946.476 | 52665.545 | +1 % |
| `csv_table_pipeline` | 66 | 389 | +486 % | 31712.126 | 31717.713 | +0 % |
| `chacha20` | 37 | 442 | +1096 % | 9254.142 | 9379.862 | +1 % |
| `poly1305` | 33 | 407 | +1149 % | 26123.686 | 26213.227 | +0 % |
| `blake2b` | 40 | 378 | +836 % | 11775.939 | 11952.485 | +1 % |
| `sha512` | 39 | 376 | +875 % | 13561.461 | 13775.272 | +2 % |
| `x25519` | 46 | 398 | +765 % | 65158.426 | 63071.052 | −3 % |

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
| _(floor: empty program)_ | _5.643_ | _67.275_ | _61.243_ | _28.771_ | _38.071_ | _62.525_ | _78.186_ |
| `lcg` | 5.952 | 102.166 | 62.660 | 38.147 | 37.843 | 65.489 | 75.289 |
| `packet_classifier` | 6.008 | 78.062 | 64.466 | 34.949 | 38.975 | 69.862 | 82.963 |
| `ring_write` | 11.357 | 82.953 | 76.292 | 35.139 | 38.684 | 67.502 | 78.498 |
| `histogram_bins` | 11.429 | 85.088 | 78.090 | 37.312 | 38.446 | 69.323 | 88.331 |
| `prefix_scan` | 11.606 | 86.580 | 78.652 | 37.510 | 38.428 | 69.901 | 81.602 |
| `binary_search` | 11.475 | 85.574 | 77.584 | 35.167 | 38.883 | 71.473 | 231.985 |
| `sort_window` | 11.645 | 89.769 | 83.480 | 39.329 | 38.764 | 76.082 | 85.542 |
| `bloom_filter` | 12.139 | 88.822 | 83.526 | 38.756 | 38.793 | 72.257 | 81.252 |
| `hash_join` | 14.893 | 140.071 | 125.410 | 57.601 | 38.821 | 100.335 | 113.432 |
| `sieve` | 11.851 | 88.182 | 81.552 | 41.323 | 38.387 | 80.012 | 86.801 |
| `fib` | 6.139 | 76.803 | 64.662 | 34.816 | 38.376 | 67.864 | 78.723 |
| `collatz` | 6.053 | 77.003 | 67.135 | 34.950 | 38.135 | 72.312 | 79.250 |
| `matmul` | 12.115 | 92.055 | 81.732 | 42.301 | 39.202 | 86.234 | 92.768 |
| `json_parse` | 38.146 | 285.644 | 267.645 | 60.472 | 38.954 | 149.797 | 143.533 |
| `nbody` | 12.858 | 92.976 | 94.947 | 49.583 | 38.603 | 86.181 | 95.214 |
| `safe_record_array` | 14.761 | 179.270 | 111.339 | 45.790 | 41.050 | 90.441 | 104.208 |
| `payload_state_machine` | 21.808 | 181.112 | 130.373 | 47.210 | 38.129 | 90.416 | 96.008 |
| `captured_closure_queue` | 17.511 | 212.735 | 141.837 | 47.510 | 38.804 | 111.027 | 111.464 |
| `dynamic_method_mix` | 17.288 | 209.034 | 136.137 | 45.834 | 37.557 | 104.489 | 106.591 |
| `csv_table_pipeline` | 67.247 | 484.328 | 442.813 | 119.870 | 38.631 | 209.418 | 212.285 |
| `chacha20` | 52.692 | 441.572 | 638.236 | 55.433 | 38.136 | 100.381 | 109.375 |
| `poly1305` | 43.015 | 302.572 | 320.704 | 60.121 | 37.966 | 122.869 | 119.887 |
| `blake2b` | 28.473 | 275.970 | 215.227 | 55.322 | 38.366 | 112.361 | 118.025 |
| `sha512` | 27.715 | 294.847 | 205.889 | 49.624 | 38.017 | 100.981 | 106.767 |
| `x25519` | 39.561 | 1018.866 | 673.279 | 447.727 | 38.686 | 519.903 | 531.991 |

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
