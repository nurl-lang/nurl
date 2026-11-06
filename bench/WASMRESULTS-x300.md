# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-06T18:19:50Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `a3be3e7c7302008216b075e2746e99a350284802` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42255071453 |
| NURL | `v0.89.0-4-ga3be3e7c` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.8), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.3 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _3.441_ | _13.291_ | _3.9_ | _3.406_ | _9.625_ | _2.8_ | _3.535_ | _33.180_ | _9.4_ |
| `lcg` | 11210.792 | 11216.372 | 1.0 | 11189.918 | 11214.085 | 1.0 | 11192.878 | 11225.129 | 1.0 |
| `packet_classifier` | 16312.943 | 15184.631 | 0.9 | 16322.843 | 15182.402 | 0.9 | 16338.272 | 15180.919 | 0.9 |
| `ring_write` | 12123.980 | 14973.592 | 1.2 | 12129.150 | 14958.350 | 1.2 | 12129.271 | 14947.173 | 1.2 |
| `histogram_bins` | 11196.055 | 14522.589 | 1.3 | 11396.544 | 14473.362 | 1.3 | 11203.200 | 14291.788 | 1.3 |
| `prefix_scan` | 6035.393 | 2550.618 | 0.4 | 6030.685 | 2590.348 | 0.4 | 6031.990 | 2557.114 | 0.4 |
| `binary_search` | 10741.950 | 17097.007 | 1.6 | 10827.575 | 17957.269 | 1.7 | 12289.156 | 17952.641 | 1.5 |
| `sort_window` | 7653.259 | 12432.162 | 1.6 | 18508.798 | 8722.465 | 0.5 | 7469.548 | 8918.055 | 1.2 |
| `bloom_filter` | 4132.643 | 4551.684 | 1.1 | 4944.385 | 4684.111 | 0.9 | 4945.321 | 4393.390 | 0.9 |
| `hash_join` | 7411.426 | 12652.843 | 1.7 | 8427.512 | 12470.489 | 1.5 | 8477.590 | 12390.598 | 1.5 |
| `sieve` | 5300.027 | 7398.401 | 1.4 | 5290.223 | 6038.264 | 1.1 | 5279.847 | 6056.675 | 1.1 |
| `fib` | 7028.799 | 12297.172 | 1.7 | 8441.239 | 12135.267 | 1.4 | 7869.654 | 11261.364 | 1.4 |
| `collatz` | 4861.999 | 7957.814 | 1.6 | 4855.658 | 7952.360 | 1.6 | 4863.356 | 7946.917 | 1.6 |
| `matmul` | 9305.829 | 8654.278 | 0.9 | 9291.854 | 7477.214 | 0.8 | 9294.949 | 6974.914 | 0.8 |
| `json_parse` | 1245.860 | 3298.006 | 2.6 | 2840.149 | 1777.889 | 0.6 | 4299.946 | 3318.276 | 0.8 |
| `nbody` | 11677.240 | 13057.788 | 1.1 | 11694.192 | 11425.748 | 1.0 | 11091.977 | 11559.010 | 1.0 |
| `chacha20` | 1797.832 | 11695.555 | 6.5 | 12216.213 | 12750.830 | 1.0 | 13204.026 | 12858.755 | 1.0 |
| `poly1305` | 3117.802 | 33115.850 | 10.6 | 5798.527 | 35005.841 | 6.0 | 5804.655 | 40757.283 | 7.0 |
| `blake2b` | 12656.466 | 13932.896 | 1.1 | 19518.274 | 21307.148 | 1.1 | 20073.281 | 26495.214 | 1.3 |
| `sha512` | 13591.870 | 16033.901 | 1.2 | 14762.023 | 16996.057 | 1.2 | 15081.550 | 17520.927 | 1.2 |
| `x25519` | 9028.245 | 87063.605 | 9.6 | 15958.816 | 110505.225 | 6.9 | 15140.203 | 127169.130 | 8.4 |

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
| `histogram_bins` | 1.3 | 1.3 | 1.3 | 1.3 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 1.6 | 1.6 | 1.7 | 1.5 |
| `sort_window` | 1.6 | 1.6 | 0.5 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 0.9 | 0.9 |
| `hash_join` | 1.7 | 1.7 | 1.5 | 1.5 |
| `sieve` | 1.4 | 1.2 | 1.1 | 1.1 |
| `fib` | 1.7 | 1.6 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.6 | 2.6 | 0.6 | 0.8 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 6.5 | 6.5 | 1.0 | 1.0 |
| `poly1305` | 10.6 | 10.7 | 6.0 | 7.0 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 9.6 | 9.4 | 6.9 | 8.4 |

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
| _(floor: empty program)_ | _13.291_ | _5.808_ | _9.625_ | _**5.646**_ | _33.180_ | _7.298_ |
| `lcg` | 11216.372 | **11196.636** | 11214.085 | 11201.127 | 11225.129 | 11201.568 |
| `packet_classifier` | 15184.631 | **13984.563** | 15182.402 | 14001.106 | 15180.919 | 14016.468 |
| `ring_write` | 14973.592 | **13064.437** | 14958.350 | 13070.313 | 14947.173 | 13070.680 |
| `histogram_bins` | 14522.589 | 11645.513 | 14473.362 | 12020.348 | 14291.788 | **11234.947** |
| `prefix_scan` | 2550.618 | **1874.773** | 2590.348 | 2438.835 | 2557.114 | 1880.390 |
| `binary_search` | 17097.007 | **14205.685** | 17957.269 | 14379.932 | 17952.641 | 15506.407 |
| `sort_window` | 12432.162 | 13271.353 | **8722.465** | 12686.322 | 8918.055 | 12094.196 |
| `bloom_filter` | 4551.684 | **3494.692** | 4684.111 | 3683.137 | 4393.390 | 3698.794 |
| `hash_join` | 12652.843 | 11030.331 | 12470.489 | **10985.514** | 12390.598 | 11065.337 |
| `sieve` | 7398.401 | **5723.360** | 6038.264 | 5933.204 | 6056.675 | 5873.082 |
| `fib` | 12297.172 | 10507.761 | 12135.267 | 9613.722 | 11261.364 | **8467.397** |
| `collatz` | 7957.814 | **7932.385** | 7952.360 | 7946.470 | 7946.917 | 7936.977 |
| `matmul` | 8654.278 | 7837.177 | 7477.214 | **6545.606** | 6974.914 | 6733.131 |
| `json_parse` | 3298.006 | 3498.577 | **1777.889** | 1894.298 | 3318.276 | 4008.742 |
| `nbody` | 13057.788 | 12599.102 | **11425.748** | 11536.690 | 11559.010 | 13182.517 |
| `chacha20` | 11695.555 | **11449.686** | 12750.830 | 14853.266 | 12858.755 | 15185.087 |
| `poly1305` | 33115.850 | 21485.978 | 35005.841 | 16451.376 | 40757.283 | **16276.870** |
| `blake2b` | **13932.896** | 17775.124 | 21307.148 | 24236.356 | 26495.214 | 30206.724 |
| `sha512` | **16033.901** | 19317.802 | 16996.057 | 17875.578 | 17520.927 | 17903.580 |
| `x25519` | 87063.605 | **42702.473** | 110505.225 | 44945.287 | 127169.130 | 45809.070 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _5.808_ | _0.4_ | _1.7_ | _0.6_ | _0.2_ |
| `lcg` | 11196.636 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 13984.563 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 13064.437 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 11645.513 | 0.8 | 1.0 | 0.8 | 0.8 |
| `prefix_scan` | 1874.773 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 14205.685 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 13271.353 | 1.1 | 1.7 | 1.5 | 1.4 |
| `bloom_filter` | 3494.692 | 0.8 | 0.8 | 0.8 | 0.8 |
| `hash_join` | 11030.331 | 0.9 | 1.5 | 0.9 | 0.9 |
| `sieve` | 5723.360 | 0.8 | 1.1 | 1.0 | 1.0 |
| `fib` | 10507.761 | 0.9 | 1.5 | 0.8 | 0.8 |
| `collatz` | 7932.385 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 7837.177 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 3498.577 | 1.1 | 2.8 | 1.1 | 1.2 |
| `nbody` | 12599.102 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 11449.686 | 1.0 | 6.4 | 1.2 | 1.2 |
| `poly1305` | 21485.978 | 0.6 | 6.9 | 0.5 | 0.4 |
| `blake2b` | 17775.124 | 1.3 | 1.4 | 1.1 | 1.1 |
| `sha512` | 19317.802 | 1.2 | 1.4 | 1.1 | 1.0 |
| `x25519` | 42702.473 | 0.5 | 4.7 | 0.4 | 0.4 |

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
| `hash_join` | 26 | 28 | 16 | 924 | 4434 | 2127 |
| `sieve` | 18 | 26 | 16 | 916 | 4431 | 2124 |
| `fib` | 18 | 26 | 16 | 915 | 4431 | 2124 |
| `collatz` | 18 | 26 | 16 | 915 | 4431 | 2124 |
| `matmul` | 18 | 27 | 16 | 917 | 4432 | 2125 |
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
| _(floor: empty program)_ | _4_ | _320_ | _+7935 %_ | _13.291_ | _158.179_ | _+1090 %_ |
| `lcg` | 26 | 320 | +1121 % | 11216.372 | 11353.899 | +1 % |
| `packet_classifier` | 26 | 320 | +1123 % | 15184.631 | 15316.501 | +1 % |
| `ring_write` | 26 | 320 | +1120 % | 14973.592 | 15069.190 | +1 % |
| `histogram_bins` | 26 | 320 | +1118 % | 14522.589 | 14665.714 | +1 % |
| `prefix_scan` | 27 | 320 | +1104 % | 2550.618 | 2680.631 | +5 % |
| `binary_search` | 26 | 320 | +1115 % | 17097.007 | 17222.391 | +1 % |
| `sort_window` | 27 | 321 | +1106 % | 12432.162 | 12557.768 | +1 % |
| `bloom_filter` | 26 | 320 | +1111 % | 4551.684 | 4637.171 | +2 % |
| `hash_join` | 28 | 323 | +1040 % | 12652.843 | 12879.042 | +2 % |
| `sieve` | 26 | 320 | +1118 % | 7398.401 | 6320.950 | −15 % |
| `fib` | 26 | 320 | +1122 % | 12297.172 | 11693.277 | −5 % |
| `collatz` | 26 | 320 | +1124 % | 7957.814 | 8081.440 | +2 % |
| `matmul` | 27 | 320 | +1107 % | 8654.278 | 8799.777 | +2 % |
| `json_parse` | 46 | 335 | +624 % | 3298.006 | 3429.949 | +4 % |
| `nbody` | 28 | 322 | +1047 % | 13057.788 | 13261.201 | +2 % |
| `chacha20` | 40 | 401 | +894 % | 11695.555 | 11877.675 | +2 % |
| `poly1305` | 34 | 361 | +950 % | 33115.850 | 33337.999 | +1 % |
| `blake2b` | 42 | 333 | +686 % | 13932.896 | 14073.876 | +1 % |
| `sha512` | 41 | 331 | +716 % | 16033.901 | 16036.556 | +0 % |
| `x25519` | 47 | 352 | +642 % | 87063.605 | 84919.224 | −2 % |

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
| _(floor: empty program)_ | _6.704_ | _126.148_ | _56.195_ | _60.272_ | _45.983_ | _65.671_ | _79.208_ |
| `lcg` | 6.986 | 141.802 | 58.230 | 71.822 | 46.796 | 74.346 | 84.439 |
| `packet_classifier` | 6.996 | 147.794 | 58.252 | 71.468 | 45.522 | 74.955 | 84.853 |
| `ring_write` | 15.473 | 151.825 | 69.093 | 71.279 | 44.447 | 77.279 | 85.482 |
| `histogram_bins` | 15.762 | 156.732 | 69.583 | 74.038 | 44.761 | 79.763 | 88.030 |
| `prefix_scan` | 15.664 | 155.253 | 70.141 | 75.667 | 44.710 | 77.788 | 87.932 |
| `binary_search` | 15.868 | 152.523 | 68.517 | 69.843 | 43.925 | 77.916 | 88.467 |
| `sort_window` | 15.858 | 164.107 | 71.147 | 76.420 | 46.155 | 83.121 | 93.144 |
| `bloom_filter` | 16.542 | 161.138 | 72.840 | 78.038 | 45.351 | 79.945 | 89.548 |
| `hash_join` | 19.885 | 275.550 | 84.438 | 121.884 | 45.692 | 117.080 | 126.288 |
| `sieve` | 15.760 | 159.779 | 71.697 | 83.917 | 46.298 | 91.401 | 97.363 |
| `fib` | 6.961 | 137.659 | 56.081 | 68.425 | 43.913 | 72.455 | 83.087 |
| `collatz` | 7.115 | 139.841 | 56.618 | 67.697 | 44.113 | 72.498 | 82.686 |
| `matmul` | 16.110 | 159.550 | 69.631 | 82.123 | 43.739 | 94.906 | 102.083 |
| `json_parse` | 47.127 | 458.725 | 162.120 | 121.272 | 63.369 | 175.693 | 157.868 |
| `nbody` | 17.580 | 167.471 | 79.712 | 96.370 | 44.188 | 96.133 | 105.459 |
| `chacha20` | 66.397 | 771.865 | 208.714 | 110.792 | 43.751 | 115.439 | 123.096 |
| `poly1305` | 55.010 | 502.440 | 146.472 | 105.020 | 44.330 | 123.615 | 132.735 |
| `blake2b` | 36.473 | 448.624 | 113.341 | 111.732 | 44.005 | 130.803 | 134.366 |
| `sha512` | 35.739 | 430.322 | 123.761 | 103.357 | 47.247 | 117.705 | 127.840 |
| `x25519` | 51.830 | 1573.178 | 160.605 | 753.027 | 46.236 | 651.695 | 672.157 |

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
