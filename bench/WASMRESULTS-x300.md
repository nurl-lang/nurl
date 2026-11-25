# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-25T12:25:46Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16365620 KiB |
| Commit | `c46fd726f851b3938d5fbdea2c3dc3edabd20edf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45588665887 |
| NURL | `v0.94.0-88-gc46fd726f` |
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
| _(floor: empty program)_ | _2.879_ | _11.849_ | _4.1_ | _2.870_ | _8.010_ | _2.8_ | _3.090_ | _33.826_ | _10.9_ |
| `lcg` | 11719.570 | 11745.360 | 1.0 | 11719.453 | 11756.181 | 1.0 | 11720.924 | 11763.922 | 1.0 |
| `packet_classifier` | 19435.621 | 14865.138 | 0.8 | 21338.046 | 14914.192 | 0.7 | 21001.291 | 15579.457 | 0.7 |
| `ring_write` | 13358.374 | 16136.923 | 1.2 | 13314.063 | 16139.004 | 1.2 | 13420.232 | 16146.784 | 1.2 |
| `histogram_bins` | 12085.256 | 14543.392 | 1.2 | 12091.795 | 14345.965 | 1.2 | 12106.116 | 14415.649 | 1.2 |
| `prefix_scan` | 6360.733 | 2183.953 | 0.3 | 6257.472 | 2241.027 | 0.4 | 6369.702 | 2190.834 | 0.3 |
| `binary_search` | 7866.808 | 16725.295 | 2.1 | 7736.438 | 15868.678 | 2.1 | 13475.040 | 17671.261 | 1.3 |
| `sort_window` | 12161.583 | 13234.498 | 1.1 | 22080.555 | 9980.742 | 0.5 | 11858.996 | 9937.763 | 0.8 |
| `bloom_filter` | 3858.200 | 3953.543 | 1.0 | 3930.262 | 3520.686 | 0.9 | 3904.835 | 3593.226 | 0.9 |
| `hash_join` | 6748.324 | 12524.466 | 1.9 | 8157.366 | 10113.406 | 1.2 | 7729.729 | 12855.384 | 1.7 |
| `sieve` | 10805.596 | 11449.372 | 1.1 | 10964.161 | 13231.776 | 1.2 | 10801.366 | 12456.541 | 1.2 |
| `fib` | 8324.049 | 12004.743 | 1.4 | 7317.129 | 12139.776 | 1.7 | 8324.609 | 11219.916 | 1.3 |
| `collatz` | 6725.480 | 8480.978 | 1.3 | 6745.734 | 8400.470 | 1.2 | 6729.586 | 8410.146 | 1.2 |
| `matmul` | 5569.010 | 4981.413 | 0.9 | 5543.291 | 4805.532 | 0.9 | 5590.074 | 5001.590 | 0.9 |
| `json_parse` | 1105.911 | 2808.919 | 2.5 | 2303.956 | 1733.742 | 0.8 | 3290.060 | 2575.603 | 0.8 |
| `nbody` | 9396.858 | 9892.294 | 1.1 | 9801.101 | 9127.561 | 0.9 | 8617.180 | 9222.468 | 1.1 |
| `safe_record_array` | 18743.339 | 23356.957 | 1.2 | 17945.725 | 22229.513 | 1.2 | 19741.023 | 22422.743 | 1.1 |
| `payload_state_machine` | 24945.756 | 53144.417 | 2.1 | 24690.052 | 38294.381 | 1.6 | 24749.713 | 36060.342 | 1.5 |
| `captured_closure_queue` | 32474.831 | 51682.682 | 1.6 | 27362.070 | 47854.333 | 1.7 | 33447.555 | 51494.935 | 1.5 |
| `dynamic_method_mix` | 36660.740 | 58353.151 | 1.6 | 35969.296 | 55064.674 | 1.5 | 35463.610 | 56611.226 | 1.6 |
| `csv_table_pipeline` | 19896.070 | 43074.594 | 2.2 | 28225.459 | 34000.127 | 1.2 | 20382.810 | 32452.342 | 1.6 |
| `chacha20` | 993.347 | 9546.294 | 9.6 | 9823.780 | 11806.474 | 1.2 | 10038.827 | 11640.876 | 1.2 |
| `poly1305` | 2677.638 | 24420.063 | 9.1 | 6526.095 | 23908.502 | 3.7 | 6534.690 | 29258.480 | 4.5 |
| `blake2b` | 12058.033 | 12631.696 | 1.0 | 14549.616 | 16330.182 | 1.1 | 15486.655 | 23707.074 | 1.5 |
| `sha512` | 12168.386 | 14917.480 | 1.2 | 12795.593 | 16500.891 | 1.3 | 13210.659 | 15404.897 | 1.2 |
| `x25519` | 8374.751 | 64899.416 | 7.7 | 13728.003 | 76124.818 | 5.5 | 13000.698 | 94399.699 | 7.3 |

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
| `packet_classifier` | 0.8 | 0.8 | 0.7 | 0.7 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.2 |
| `histogram_bins` | 1.2 | 1.2 | 1.2 | 1.2 |
| `prefix_scan` | 0.3 | 0.3 | 0.4 | 0.3 |
| `binary_search` | 2.1 | 2.1 | 2.1 | 1.3 |
| `sort_window` | 1.1 | 1.1 | 0.5 | 0.8 |
| `bloom_filter` | 1.0 | 1.0 | 0.9 | 0.9 |
| `hash_join` | 1.9 | 1.8 | 1.2 | 1.7 |
| `sieve` | 1.1 | 1.1 | 1.2 | 1.2 |
| `fib` | 1.4 | 1.4 | 1.7 | 1.3 |
| `collatz` | 1.3 | 1.2 | 1.2 | 1.2 |
| `matmul` | 0.9 | 0.9 | 0.9 | 0.9 |
| `json_parse` | 2.5 | 2.5 | 0.7 | 0.8 |
| `nbody` | 1.1 | 1.0 | 0.9 | 1.1 |
| `safe_record_array` | 1.2 | 1.3 | 1.2 | 1.1 |
| `payload_state_machine` | 2.1 | 2.1 | 1.6 | 1.5 |
| `captured_closure_queue` | 1.6 | 1.6 | 1.7 | 1.5 |
| `dynamic_method_mix` | 1.6 | 1.6 | 1.5 | 1.6 |
| `csv_table_pipeline` | 2.2 | 2.1 | 1.2 | 1.6 |
| `chacha20` | 9.6 | 9.6 | 1.2 | 1.2 |
| `poly1305` | 9.1 | 9.1 | 3.7 | 4.5 |
| `blake2b` | 1.0 | 1.0 | 1.1 | 1.5 |
| `sha512` | 1.2 | 1.2 | 1.3 | 1.2 |
| `x25519` | 7.8 | 7.8 | 5.5 | 7.3 |

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
| _(floor: empty program)_ | _11.849_ | _4.895_ | _8.010_ | _**4.369**_ | _33.826_ | _5.595_ |
| `lcg` | 11745.360 | 11729.223 | 11756.181 | 11731.558 | 11763.922 | **11726.907** |
| `packet_classifier` | 14865.138 | **14749.228** | 14914.192 | 14841.165 | 15579.457 | 14961.619 |
| `ring_write` | 16136.923 | **13684.885** | 16139.004 | 13714.866 | 16146.784 | 13724.100 |
| `histogram_bins` | 14543.392 | 12149.521 | 14345.965 | 12371.343 | 14415.649 | **12134.873** |
| `prefix_scan` | 2183.953 | **1989.574** | 2241.027 | 2292.202 | 2190.834 | 2007.465 |
| `binary_search` | 16725.295 | 14652.410 | 15868.678 | **14566.015** | 17671.261 | 16369.561 |
| `sort_window` | 13234.498 | 14683.912 | 9980.742 | 9536.169 | 9937.763 | **9223.811** |
| `bloom_filter` | 3953.543 | **2972.247** | 3520.686 | 3178.840 | 3593.226 | 2985.801 |
| `hash_join` | 12524.466 | 10499.336 | **10113.406** | 10865.097 | 12855.384 | 10590.111 |
| `sieve` | 11449.372 | 12206.541 | 13231.776 | 12383.598 | 12456.541 | **11288.977** |
| `fib` | 12004.743 | 8211.010 | 12139.776 | 8171.929 | 11219.916 | **7692.442** |
| `collatz` | 8480.978 | 7707.449 | 8400.470 | 7652.519 | 8410.146 | **7413.876** |
| `matmul` | 4981.413 | 5029.676 | **4805.532** | 5076.641 | 5001.590 | 4934.136 |
| `json_parse` | 2808.919 | 2816.653 | 1733.742 | **1306.227** | 2575.603 | 2677.564 |
| `nbody` | 9892.294 | 9642.182 | **9127.561** | 9181.454 | 9222.468 | 9624.941 |
| `safe_record_array` | 23356.957 | 24379.128 | **22229.513** | 23435.270 | 22422.743 | 23720.735 |
| `payload_state_machine` | 53144.417 | 55051.650 | 38294.381 | 36149.009 | **36060.342** | 36931.417 |
| `captured_closure_queue` | 51682.682 | 54770.443 | **47854.333** | 49708.196 | 51494.935 | 52745.563 |
| `dynamic_method_mix` | 58353.151 | 64136.702 | **55064.674** | 62569.177 | 56611.226 | 61337.729 |
| `csv_table_pipeline` | 43074.594 | 39948.166 | 34000.127 | 31942.076 | 32452.342 | **31311.978** |
| `chacha20` | 9546.294 | **9035.062** | 11806.474 | 12458.932 | 11640.876 | 11992.441 |
| `poly1305` | 24420.063 | 18626.610 | 23908.502 | **17095.068** | 29258.480 | 17549.210 |
| `blake2b` | 12631.696 | **12516.923** | 16330.182 | 18820.457 | 23707.074 | 23008.686 |
| `sha512` | **14917.480** | 15990.753 | 16500.891 | 17422.265 | 15404.897 | 16561.748 |
| `x25519` | 64899.416 | 38034.241 | 76124.818 | 37950.462 | 94399.699 | **37816.551** |

`nwasm` is faster than the reference runtime on 16 of 25 NURL modules,
15 of 25 C modules and 17 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.895_ | _0.4_ | _1.7_ | _0.5_ | _0.2_ |
| `lcg` | 11729.223 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 14749.228 | 1.0 | 0.8 | 1.0 | 1.0 |
| `ring_write` | 13684.885 | 0.8 | 1.0 | 0.8 | 0.8 |
| `histogram_bins` | 12149.521 | 0.8 | 1.0 | 0.9 | 0.8 |
| `prefix_scan` | 1989.574 | 0.9 | 0.3 | 1.0 | 0.9 |
| `binary_search` | 14652.410 | 0.9 | 1.9 | 0.9 | 0.9 |
| `sort_window` | 14683.912 | 1.1 | 1.2 | 1.0 | 0.9 |
| `bloom_filter` | 2972.247 | 0.8 | 0.8 | 0.9 | 0.8 |
| `hash_join` | 10499.336 | 0.8 | 1.6 | 1.1 | 0.8 |
| `sieve` | 12206.541 | 1.1 | 1.1 | 0.9 | 0.9 |
| `fib` | 8211.010 | 0.7 | 1.0 | 0.7 | 0.7 |
| `collatz` | 7707.449 | 0.9 | 1.1 | 0.9 | 0.9 |
| `matmul` | 5029.676 | 1.0 | 0.9 | 1.1 | 1.0 |
| `json_parse` | 2816.653 | 1.0 | 2.5 | 0.8 | 1.0 |
| `nbody` | 9642.182 | 1.0 | 1.0 | 1.0 | 1.0 |
| `safe_record_array` | 24379.128 | 1.0 | 1.3 | 1.1 | 1.1 |
| `payload_state_machine` | 55051.650 | 1.0 | 2.2 | 0.9 | 1.0 |
| `captured_closure_queue` | 54770.443 | 1.1 | 1.7 | 1.0 | 1.0 |
| `dynamic_method_mix` | 64136.702 | 1.1 | 1.7 | 1.1 | 1.1 |
| `csv_table_pipeline` | 39948.166 | 0.9 | 2.0 | 0.9 | 1.0 |
| `chacha20` | 9035.062 | 0.9 | 9.1 | 1.1 | 1.0 |
| `poly1305` | 18626.610 | 0.8 | 7.0 | 0.7 | 0.6 |
| `blake2b` | 12516.923 | 1.0 | 1.0 | 1.2 | 1.0 |
| `sha512` | 15990.753 | 1.1 | 1.3 | 1.1 | 1.1 |
| `x25519` | 38034.241 | 0.6 | 4.5 | 0.5 | 0.4 |

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
| _(floor: empty program)_ | _4_ | _366_ | _+9314 %_ | _11.849_ | _158.829_ | _+1240 %_ |
| `lcg` | 25 | 366 | +1372 % | 11745.360 | 11889.373 | +1 % |
| `packet_classifier` | 25 | 366 | +1374 % | 14865.138 | 15029.034 | +1 % |
| `ring_write` | 25 | 366 | +1370 % | 16136.923 | 16267.412 | +1 % |
| `histogram_bins` | 25 | 366 | +1367 % | 14543.392 | 14665.202 | +1 % |
| `prefix_scan` | 25 | 366 | +1350 % | 2183.953 | 2330.366 | +7 % |
| `binary_search` | 25 | 366 | +1364 % | 16725.295 | 16779.768 | +0 % |
| `sort_window` | 25 | 367 | +1351 % | 13234.498 | 13636.747 | +3 % |
| `bloom_filter` | 25 | 367 | +1358 % | 3953.543 | 4081.853 | +3 % |
| `hash_join` | 27 | 369 | +1266 % | 12524.466 | 12525.004 | +0 % |
| `sieve` | 25 | 366 | +1368 % | 11449.372 | 11666.545 | +2 % |
| `fib` | 25 | 366 | +1374 % | 12004.743 | 12177.208 | +1 % |
| `collatz` | 25 | 366 | +1375 % | 8480.978 | 8521.023 | +0 % |
| `matmul` | 25 | 366 | +1353 % | 4981.413 | 5156.745 | +4 % |
| `json_parse` | 44 | 380 | +758 % | 2808.919 | 2944.287 | +5 % |
| `nbody` | 27 | 368 | +1276 % | 9892.294 | 10012.035 | +1 % |
| `safe_record_array` | 34 | 369 | +999 % | 23356.957 | 23727.620 | +2 % |
| `payload_state_machine` | 31 | 369 | +1086 % | 53144.417 | 53522.413 | +1 % |
| `captured_closure_queue` | 36 | 371 | +924 % | 51682.682 | 52994.241 | +3 % |
| `dynamic_method_mix` | 35 | 371 | +955 % | 58353.151 | 58915.763 | +1 % |
| `csv_table_pipeline` | 66 | 389 | +486 % | 43074.594 | 41997.697 | −3 % |
| `chacha20` | 37 | 442 | +1096 % | 9546.294 | 9710.777 | +2 % |
| `poly1305` | 33 | 407 | +1149 % | 24420.063 | 24632.619 | +1 % |
| `blake2b` | 40 | 378 | +836 % | 12631.696 | 12779.399 | +1 % |
| `sha512` | 39 | 376 | +875 % | 14917.480 | 15067.823 | +1 % |
| `x25519` | 46 | 398 | +765 % | 64899.416 | 65457.308 | +1 % |

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
| _(floor: empty program)_ | _6.324_ | _76.249_ | _60.583_ | _29.815_ | _36.686_ | _71.383_ | _83.298_ |
| `lcg` | 6.044 | 83.523 | 69.593 | 34.303 | 37.470 | 71.165 | 83.980 |
| `packet_classifier` | 6.310 | 82.129 | 63.520 | 34.088 | 36.029 | 69.146 | 81.898 |
| `ring_write` | 13.707 | 97.582 | 82.182 | 37.548 | 40.604 | 74.388 | 92.134 |
| `histogram_bins` | 13.511 | 100.222 | 83.856 | 39.857 | 37.767 | 77.538 | 89.093 |
| `prefix_scan` | 12.723 | 94.873 | 77.519 | 37.647 | 34.946 | 70.196 | 83.807 |
| `binary_search` | 13.355 | 100.839 | 81.149 | 36.760 | 37.861 | 78.657 | 90.209 |
| `sort_window` | 13.499 | 102.981 | 88.300 | 41.930 | 37.920 | 82.305 | 99.788 |
| `bloom_filter` | 13.225 | 95.595 | 82.358 | 38.128 | 34.670 | 72.987 | 86.082 |
| `hash_join` | 16.781 | 160.885 | 135.524 | 63.829 | 36.335 | 110.414 | 125.616 |
| `sieve` | 13.216 | 100.536 | 86.686 | 44.249 | 37.871 | 88.357 | 96.805 |
| `fib` | 6.222 | 83.098 | 63.222 | 34.460 | 35.293 | 69.861 | 80.755 |
| `collatz` | 6.385 | 84.035 | 66.258 | 34.732 | 35.778 | 70.230 | 82.525 |
| `matmul` | 13.304 | 101.408 | 82.892 | 43.708 | 38.849 | 93.112 | 102.046 |
| `json_parse` | 44.796 | 355.717 | 303.249 | 68.212 | 36.670 | 177.096 | 157.425 |
| `nbody` | 14.877 | 108.386 | 103.554 | 56.032 | 37.764 | 95.986 | 107.131 |
| `safe_record_array` | 16.031 | 212.860 | 114.637 | 42.001 | 35.553 | 94.997 | 102.572 |
| `payload_state_machine` | 26.523 | 193.500 | 146.835 | 48.785 | 36.958 | 103.208 | 111.681 |
| `captured_closure_queue` | 21.265 | 273.933 | 152.877 | 52.866 | 37.107 | 130.386 | 127.580 |
| `dynamic_method_mix` | 20.131 | 263.627 | 148.248 | 49.903 | 36.625 | 133.321 | 121.638 |
| `csv_table_pipeline` | 80.052 | 614.519 | 508.931 | 144.366 | 35.707 | 253.688 | 257.449 |
| `chacha20` | 59.218 | 544.229 | 750.772 | 61.190 | 35.973 | 113.520 | 122.763 |
| `poly1305` | 50.132 | 370.842 | 371.450 | 68.056 | 37.174 | 123.126 | 132.710 |
| `blake2b` | 33.163 | 341.473 | 249.306 | 62.237 | 36.540 | 132.150 | 138.080 |
| `sha512` | 31.816 | 366.803 | 233.502 | 53.659 | 34.893 | 113.764 | 120.105 |
| `x25519` | 45.928 | 1311.526 | 810.451 | 545.995 | 37.054 | 623.144 | 633.694 |

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
