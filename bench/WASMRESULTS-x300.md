# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-13T23:48:58Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `ab45d9db114a58fdab60f618c679e8af95643b5d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43512084687 |
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
| _(floor: empty program)_ | _3.379_ | _10.719_ | _3.2_ | _3.328_ | _8.143_ | _2.4_ | _3.415_ | _28.645_ | _8.4_ |
| `lcg` | 9821.319 | 9844.351 | 1.0 | 9824.888 | 9840.449 | 1.0 | 9818.513 | 9853.198 | 1.0 |
| `packet_classifier` | 14356.427 | 13331.101 | 0.9 | 14356.988 | 13382.125 | 0.9 | 14316.279 | 13346.044 | 0.9 |
| `ring_write` | 10669.496 | 13120.063 | 1.2 | 10653.180 | 13138.388 | 1.2 | 10639.644 | 13143.022 | 1.2 |
| `histogram_bins` | 9938.509 | 12734.378 | 1.3 | 9949.075 | 11875.081 | 1.2 | 9942.194 | 12573.907 | 1.3 |
| `prefix_scan` | 5291.284 | 2238.641 | 0.4 | 5295.325 | 2177.513 | 0.4 | 5289.011 | 2245.617 | 0.4 |
| `binary_search` | 7314.768 | 14280.729 | 2.0 | 7366.479 | 15075.116 | 2.0 | 10677.929 | 14769.182 | 1.4 |
| `sort_window` | 6748.426 | 9459.233 | 1.4 | 15545.097 | 7938.032 | 0.5 | 6550.515 | 7746.043 | 1.2 |
| `bloom_filter` | 3607.515 | 3963.559 | 1.1 | 4345.690 | 4110.987 | 0.9 | 4349.179 | 3866.023 | 0.9 |
| `hash_join` | 5761.656 | 9436.216 | 1.6 | 6670.322 | 8911.211 | 1.3 | 6704.221 | 9421.000 | 1.4 |
| `sieve` | 4186.730 | 4902.634 | 1.2 | 4098.401 | 6106.504 | 1.5 | 4107.158 | 6012.512 | 1.5 |
| `fib` | 6068.014 | 10059.736 | 1.7 | 6357.408 | 9558.513 | 1.5 | 7326.336 | 9327.364 | 1.3 |
| `collatz` | 4206.367 | 6890.669 | 1.6 | 4215.964 | 6895.874 | 1.6 | 4216.891 | 6902.527 | 1.6 |
| `matmul` | 10237.854 | 8811.534 | 0.9 | 10036.237 | 7210.867 | 0.7 | 10289.799 | 7155.911 | 0.7 |
| `json_parse` | 921.623 | 2553.108 | 2.8 | 2259.169 | 1365.976 | 0.6 | 3477.137 | 2582.273 | 0.7 |
| `nbody` | 10299.080 | 10156.980 | 1.0 | 11169.632 | 9996.192 | 0.9 | 9783.644 | 9931.569 | 1.0 |
| `safe_record_array` | 15329.166 | 21042.499 | 1.4 | 13651.051 | 17204.937 | 1.3 | 16422.082 | 17001.786 | 1.0 |
| `payload_state_machine` | 19403.131 | 46464.367 | 2.4 | 18340.171 | 26677.406 | 1.5 | 18659.939 | 26335.241 | 1.4 |
| `captured_closure_queue` | 26991.251 | 40867.102 | 1.5 | 21193.804 | 36255.000 | 1.7 | 25215.228 | 38384.247 | 1.5 |
| `dynamic_method_mix` | 29594.058 | 51158.850 | 1.7 | 31878.918 | 47321.458 | 1.5 | 29790.100 | 49447.397 | 1.7 |
| `csv_table_pipeline` | 15558.810 | 31760.570 | 2.0 | 24212.001 | 28358.424 | 1.2 | 14601.770 | 23794.038 | 1.6 |
| `chacha20` | 964.671 | 9246.886 | 9.6 | 9278.609 | 10743.985 | 1.2 | 10063.378 | 10690.946 | 1.1 |
| `poly1305` | 2798.973 | 26402.260 | 9.4 | 5093.014 | 25623.852 | 5.0 | 5099.252 | 31311.079 | 6.1 |
| `blake2b` | 10609.768 | 11326.888 | 1.1 | 16644.128 | 18643.926 | 1.1 | 17669.942 | 24135.874 | 1.4 |
| `sha512` | 11190.017 | 13655.714 | 1.2 | 11918.915 | 14023.634 | 1.2 | 12080.026 | 14279.809 | 1.2 |
| `x25519` | 7981.725 | 65281.662 | 8.2 | 14045.710 | 80652.067 | 5.7 | 13253.259 | 106321.340 | 8.0 |

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
| `binary_search` | 2.0 | 1.9 | 2.0 | 1.4 |
| `sort_window` | 1.4 | 1.4 | 0.5 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 0.9 | 0.9 |
| `hash_join` | 1.6 | 1.6 | 1.3 | 1.4 |
| `sieve` | 1.2 | 1.4 | 1.5 | 1.5 |
| `fib` | 1.7 | 1.6 | 1.5 | 1.3 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.7 | 0.7 |
| `json_parse` | 2.8 | 2.8 | 0.6 | 0.7 |
| `nbody` | 1.0 | 1.0 | 0.9 | 1.0 |
| `safe_record_array` | 1.4 | 1.4 | 1.3 | 1.0 |
| `payload_state_machine` | 2.4 | 2.3 | 1.5 | 1.4 |
| `captured_closure_queue` | 1.5 | 1.5 | 1.7 | 1.5 |
| `dynamic_method_mix` | 1.7 | 1.7 | 1.5 | 1.7 |
| `csv_table_pipeline` | 2.0 | 2.0 | 1.2 | 1.6 |
| `chacha20` | 9.6 | 9.6 | 1.2 | 1.1 |
| `poly1305` | 9.4 | 9.4 | 5.0 | 6.1 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.4 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 8.2 | 8.2 | 5.7 | 8.0 |

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
| _(floor: empty program)_ | _10.719_ | _**4.720**_ | _8.143_ | _4.864_ | _28.645_ | _6.113_ |
| `lcg` | 9844.351 | 9846.458 | 9840.449 | **9824.578** | 9853.198 | 9832.844 |
| `packet_classifier` | 13331.101 | 12280.398 | 13382.125 | **12277.448** | 13346.044 | 12318.480 |
| `ring_write` | 13120.063 | **11457.082** | 13138.388 | 11461.427 | 13143.022 | 11470.383 |
| `histogram_bins` | 12734.378 | **10209.185** | 11875.081 | 10467.897 | 12573.907 | 10214.509 |
| `prefix_scan` | 2238.641 | **1646.758** | 2177.513 | 2171.739 | 2245.617 | 1654.887 |
| `binary_search` | 14280.729 | **11908.195** | 15075.116 | 12000.550 | 14769.182 | 13080.672 |
| `sort_window` | 9459.233 | 10363.956 | 7938.032 | 9225.005 | **7746.043** | 8882.727 |
| `bloom_filter` | 3963.559 | 3271.488 | 4110.987 | **3235.645** | 3866.023 | 3251.669 |
| `hash_join` | 9436.216 | **8820.753** | 8911.211 | 8906.050 | 9421.000 | 8872.015 |
| `sieve` | 4902.634 | 5874.983 | 6106.504 | 5992.853 | 6012.512 | **4738.488** |
| `fib` | 10059.736 | 7044.668 | 9558.513 | 7051.586 | 9327.364 | **6837.566** |
| `collatz` | 6890.669 | **6838.612** | 6895.874 | 6858.664 | 6902.527 | 6846.708 |
| `matmul` | 8811.534 | 7630.708 | 7210.867 | **5027.402** | 7155.911 | 5436.379 |
| `json_parse` | 2553.108 | 2860.069 | 1365.976 | **1224.643** | 2582.273 | 2583.270 |
| `nbody` | 10156.980 | 11747.406 | 9996.192 | 10029.596 | **9931.569** | 10768.395 |
| `safe_record_array` | 21042.499 | 22055.750 | 17204.937 | 18180.386 | **17001.786** | 18089.057 |
| `payload_state_machine` | 46464.367 | 48199.757 | 26677.406 | **26181.270** | 26335.241 | 26426.515 |
| `captured_closure_queue` | 40867.102 | 48126.917 | **36255.000** | 36968.243 | 38384.247 | 43398.227 |
| `dynamic_method_mix` | 51158.850 | 55742.641 | **47321.458** | 58017.762 | 49447.397 | 59973.472 |
| `csv_table_pipeline` | 31760.570 | 30720.874 | 28358.424 | 27568.174 | 23794.038 | **23706.706** |
| `chacha20` | 9246.886 | **9216.199** | 10743.985 | 11502.817 | 10690.946 | 11682.304 |
| `poly1305` | 26402.260 | 15110.844 | 25623.852 | **13537.783** | 31311.079 | 13961.670 |
| `blake2b` | **11326.888** | 12986.225 | 18643.926 | 20312.478 | 24135.874 | 24553.168 |
| `sha512` | 13655.714 | **13234.683** | 14023.634 | 14710.968 | 14279.809 | 15246.517 |
| `x25519` | 65281.662 | 36136.801 | 80652.067 | 35997.150 | 106321.340 | **35983.914** |

`nwasm` is faster than the reference runtime on 15 of 25 NURL modules,
17 of 25 C modules and 15 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.720_ | _0.4_ | _1.4_ | _0.6_ | _0.2_ |
| `lcg` | 9846.458 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 12280.398 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 11457.082 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 10209.185 | 0.8 | 1.0 | 0.9 | 0.8 |
| `prefix_scan` | 1646.758 | 0.7 | 0.3 | 1.0 | 0.7 |
| `binary_search` | 11908.195 | 0.8 | 1.6 | 0.8 | 0.9 |
| `sort_window` | 10363.956 | 1.1 | 1.5 | 1.2 | 1.1 |
| `bloom_filter` | 3271.488 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 8820.753 | 0.9 | 1.5 | 1.0 | 0.9 |
| `sieve` | 5874.983 | 1.2 | 1.4 | 1.0 | 0.8 |
| `fib` | 7044.668 | 0.7 | 1.2 | 0.7 | 0.7 |
| `collatz` | 6838.612 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 7630.708 | 0.9 | 0.7 | 0.7 | 0.8 |
| `json_parse` | 2860.069 | 1.1 | 3.1 | 0.9 | 1.0 |
| `nbody` | 11747.406 | 1.2 | 1.1 | 1.0 | 1.1 |
| `safe_record_array` | 22055.750 | 1.0 | 1.4 | 1.1 | 1.1 |
| `payload_state_machine` | 48199.757 | 1.0 | 2.5 | 1.0 | 1.0 |
| `captured_closure_queue` | 48126.917 | 1.2 | 1.8 | 1.0 | 1.1 |
| `dynamic_method_mix` | 55742.641 | 1.1 | 1.9 | 1.2 | 1.2 |
| `csv_table_pipeline` | 30720.874 | 1.0 | 2.0 | 1.0 | 1.0 |
| `chacha20` | 9216.199 | 1.0 | 9.6 | 1.1 | 1.1 |
| `poly1305` | 15110.844 | 0.6 | 5.4 | 0.5 | 0.4 |
| `blake2b` | 12986.225 | 1.1 | 1.2 | 1.1 | 1.0 |
| `sha512` | 13234.683 | 1.0 | 1.2 | 1.0 | 1.1 |
| `x25519` | 36136.801 | 0.6 | 4.5 | 0.4 | 0.3 |

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
| `safe_record_array` | 28 | 34 | 7 | 933 | 4389 | 2139 |
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
| _(floor: empty program)_ | _4_ | _366_ | _+9308 %_ | _10.719_ | _133.464_ | _+1145 %_ |
| `lcg` | 25 | 366 | +1371 % | 9844.351 | 9975.814 | +1 % |
| `packet_classifier` | 25 | 366 | +1373 % | 13331.101 | 13451.298 | +1 % |
| `ring_write` | 25 | 366 | +1370 % | 13120.063 | 13218.607 | +1 % |
| `histogram_bins` | 25 | 366 | +1366 % | 12734.378 | 12843.901 | +1 % |
| `prefix_scan` | 25 | 366 | +1349 % | 2238.641 | 2356.972 | +5 % |
| `binary_search` | 25 | 366 | +1363 % | 14280.729 | 14358.574 | +1 % |
| `sort_window` | 25 | 367 | +1350 % | 9459.233 | 9536.828 | +1 % |
| `bloom_filter` | 25 | 366 | +1357 % | 3963.559 | 4077.664 | +3 % |
| `hash_join` | 27 | 369 | +1266 % | 9436.216 | 9499.216 | +1 % |
| `sieve` | 25 | 366 | +1367 % | 4902.634 | 6112.329 | +25 % |
| `fib` | 25 | 366 | +1373 % | 10059.736 | 9653.213 | −4 % |
| `collatz` | 25 | 366 | +1374 % | 6890.669 | 6987.238 | +1 % |
| `matmul` | 25 | 366 | +1352 % | 8811.534 | 8915.477 | +1 % |
| `json_parse` | 44 | 380 | +754 % | 2553.108 | 2660.664 | +4 % |
| `nbody` | 27 | 368 | +1275 % | 10156.980 | 10263.179 | +1 % |
| `safe_record_array` | 34 | 369 | +985 % | 21042.499 | 20974.609 | −0 % |
| `payload_state_machine` | 31 | 369 | +1081 % | 46464.367 | 44995.065 | −3 % |
| `captured_closure_queue` | 36 | 371 | +919 % | 40867.102 | 40940.303 | +0 % |
| `dynamic_method_mix` | 35 | 371 | +949 % | 51158.850 | 50363.982 | −2 % |
| `csv_table_pipeline` | 68 | 390 | +478 % | 31760.570 | 31991.570 | +1 % |
| `chacha20` | 37 | 442 | +1090 % | 9246.886 | 9386.259 | +2 % |
| `poly1305` | 33 | 407 | +1145 % | 26402.260 | 26450.879 | +0 % |
| `blake2b` | 40 | 378 | +841 % | 11326.888 | 11411.383 | +1 % |
| `sha512` | 39 | 376 | +868 % | 13655.714 | 13687.215 | +0 % |
| `x25519` | 46 | 398 | +763 % | 65281.662 | 65309.568 | +0 % |

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
| _(floor: empty program)_ | _6.685_ | _70.946_ | _64.406_ | _31.626_ | _40.051_ | _51.301_ | _64.891_ |
| `lcg` | 7.011 | 80.618 | 69.507 | 36.114 | 40.914 | 57.339 | 71.988 |
| `packet_classifier` | 7.025 | 80.621 | 68.172 | 36.376 | 40.122 | 57.329 | 68.824 |
| `ring_write` | 12.889 | 87.467 | 81.772 | 37.111 | 40.305 | 58.399 | 71.270 |
| `histogram_bins` | 12.611 | 88.093 | 81.083 | 38.086 | 38.312 | 59.556 | 69.414 |
| `prefix_scan` | 12.650 | 88.389 | 80.385 | 37.678 | 39.928 | 58.962 | 72.313 |
| `binary_search` | 12.608 | 88.484 | 79.395 | 36.453 | 39.540 | 61.837 | 75.083 |
| `sort_window` | 13.010 | 93.714 | 87.530 | 40.755 | 39.968 | 65.550 | 77.971 |
| `bloom_filter` | 13.209 | 90.513 | 85.412 | 38.929 | 41.377 | 61.471 | 74.367 |
| `hash_join` | 16.845 | 145.735 | 129.769 | 60.742 | 91.224 | 88.887 | 102.139 |
| `sieve` | 12.963 | 91.606 | 84.537 | 42.405 | 55.378 | 67.374 | 79.659 |
| `fib` | 7.098 | 79.804 | 67.677 | 35.965 | 40.461 | 57.745 | 69.150 |
| `collatz` | 6.813 | 78.664 | 68.726 | 35.358 | 39.502 | 56.356 | 68.384 |
| `matmul` | 12.795 | 118.265 | 87.820 | 43.245 | 41.612 | 74.978 | 81.988 |
| `json_parse` | 39.916 | 273.471 | 273.062 | 61.815 | 45.042 | 139.493 | 125.173 |
| `nbody` | 14.214 | 97.040 | 96.923 | 50.389 | 39.817 | 73.672 | 87.533 |
| `safe_record_array` | 15.453 | 181.340 | 113.563 | 42.569 | 39.389 | 76.513 | 88.137 |
| `payload_state_machine` | 24.010 | 159.697 | 135.996 | 44.868 | 38.940 | 80.687 | 88.969 |
| `captured_closure_queue` | 20.125 | 228.228 | 144.099 | 51.296 | 39.560 | 102.545 | 104.707 |
| `dynamic_method_mix` | 18.557 | 214.044 | 138.917 | 46.340 | 38.138 | 92.610 | 98.694 |
| `csv_table_pipeline` | 72.966 | 488.509 | 461.843 | 122.986 | 40.058 | 204.656 | 210.840 |
| `chacha20` | 59.548 | 461.914 | 675.276 | 60.132 | 41.671 | 92.573 | 110.546 |
| `poly1305` | 47.597 | 316.879 | 335.734 | 63.838 | 40.082 | 98.369 | 109.608 |
| `blake2b` | 30.701 | 283.456 | 219.733 | 58.683 | 91.536 | 104.063 | 116.066 |
| `sha512` | 29.439 | 309.153 | 214.847 | 51.692 | 40.559 | 91.738 | 100.215 |
| `x25519` | 44.018 | 1044.354 | 727.945 | 460.574 | 41.312 | 512.402 | 543.760 |

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
