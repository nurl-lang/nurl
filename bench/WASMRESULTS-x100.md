# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-21T12:27:15Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `e8bc8d72c43b70c885d9f0a5bea1994649f810bd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39594781343 |
| NURL | `v0.76.0-8-ge8bc8d72` |
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
| _(floor: empty program)_ | _1.233_ | _9.214_ | _7.5_ | _1.268_ | _5.586_ | _4.4_ | _1.399_ | _27.383_ | _19.6_ |
| `lcg` | 3272.841 | 3293.489 | 1.0 | 3272.414 | 3293.091 | 1.0 | 3275.505 | 3297.846 | 1.0 |
| `packet_classifier` | 4771.395 | 4452.228 | 0.9 | 4771.015 | 4454.182 | 0.9 | 4770.463 | 4457.248 | 0.9 |
| `ring_write` | 3546.750 | 4385.336 | 1.2 | 3545.854 | 4383.786 | 1.2 | 3544.514 | 4389.151 | 1.2 |
| `histogram_bins` | 3310.744 | 4256.920 | 1.3 | 3311.346 | 4245.518 | 1.3 | 3311.421 | 4086.075 | 1.2 |
| `prefix_scan` | 1758.519 | 763.449 | 0.4 | 1760.709 | 742.560 | 0.4 | 1763.188 | 765.263 | 0.4 |
| `binary_search` | 2523.566 | 4751.584 | 1.9 | 2608.824 | 5042.150 | 1.9 | 3417.930 | 4935.878 | 1.4 |
| `sort_window` | 2237.554 | 3538.060 | 1.6 | 2237.109 | 2687.743 | 1.2 | 2185.779 | 2606.683 | 1.2 |
| `bloom_filter` | 1202.778 | 1336.841 | 1.1 | 1431.176 | 1385.569 | 1.0 | 1445.797 | 1301.268 | 0.9 |
| `hash_join` | 2101.559 | 3267.088 | 1.6 | 2214.992 | 3256.362 | 1.5 | 2238.945 | 3309.247 | 1.5 |
| `sieve` | 1359.283 | 1992.810 | 1.5 | 1358.225 | 1575.966 | 1.2 | 1350.827 | 1560.427 | 1.2 |
| `fib` | 2428.399 | 3198.825 | 1.3 | 2431.353 | 3266.936 | 1.3 | 2115.419 | 3217.616 | 1.5 |
| `collatz` | 1311.283 | 2156.333 | 1.6 | 1307.013 | 2152.305 | 1.6 | 1312.231 | 2153.673 | 1.6 |
| `matmul` | 3332.226 | 2944.649 | 0.9 | 3367.312 | 2382.037 | 0.7 | 3383.942 | 2052.228 | 0.6 |
| `json_parse` | 470.420 | 1140.991 | 2.4 | 532.722 | 480.888 | 0.9 | 746.309 | 870.985 | 1.2 |
| `nbody` | 3428.663 | 3389.220 | 1.0 | 3428.253 | 3344.582 | 1.0 | 3249.132 | 3322.649 | 1.0 |
| `chacha20` | 569.331 | 3746.073 | 6.6 | 3430.227 | 3587.551 | 1.0 | 3364.748 | 3562.440 | 1.1 |
| `poly1305` | 1906.000 | 8748.186 | 4.6 | 1696.401 | 8600.180 | 5.1 | 1699.582 | 10860.363 | 6.4 |
| `blake2b` | 3612.206 | 3990.188 | 1.1 | 5560.508 | 6260.577 | 1.1 | 6128.149 | 7548.541 | 1.2 |
| `sha512` | 3719.622 | 4539.456 | 1.2 | 3975.764 | 4693.153 | 1.2 | 4025.835 | 4777.309 | 1.2 |
| `x25519` | 4605.880 | 25158.906 | 5.5 | 4704.673 | 26444.632 | 5.6 | 4403.279 | 34758.447 | 7.9 |

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
| `histogram_bins` | 1.3 | 1.3 | 1.3 | 1.2 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 1.9 | 1.9 | 1.9 | 1.4 |
| `sort_window` | 1.6 | 1.6 | 1.2 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.6 | 1.5 | 1.5 | 1.5 |
| `sieve` | 1.5 | 1.2 | 1.2 | 1.1 |
| `fib` | 1.3 | 1.4 | 1.3 | 1.5 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.7 | 0.6 |
| `json_parse` | 2.4 | 2.4 | 0.9 | 1.1 |
| `nbody` | 1.0 | 1.0 | 1.0 | 1.0 |
| `chacha20` | 6.6 | 6.3 | 1.0 | 1.1 |
| `poly1305` | 4.6 | 4.8 | 5.1 | 6.4 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.2 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 5.5 | 5.4 | 5.6 | 7.9 |

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
| _(floor: empty program)_ | _9.214_ | _2.562_ | _5.586_ | _**2.240**_ | _27.383_ | _3.007_ |
| `lcg` | 3293.489 | **3274.640** | 3293.091 | 3279.169 | 3297.846 | 3278.031 |
| `packet_classifier` | 4452.228 | **4093.845** | 4454.182 | 4097.520 | 4457.248 | 4095.486 |
| `ring_write` | 4385.336 | **3820.578** | 4383.786 | 3823.413 | 4389.151 | 3822.803 |
| `histogram_bins` | 4256.920 | **3405.124** | 4245.518 | 3480.338 | 4086.075 | 3408.389 |
| `prefix_scan` | 763.449 | **550.543** | 742.560 | 727.774 | 765.263 | 552.811 |
| `binary_search` | 4751.584 | **3963.320** | 5042.150 | 3992.594 | 4935.878 | 4351.999 |
| `sort_window` | 3538.060 | 3450.028 | 2687.743 | 3077.404 | **2606.683** | 2965.525 |
| `bloom_filter` | 1336.841 | 1092.693 | 1385.569 | **1079.969** | 1301.268 | 1092.360 |
| `hash_join` | 3267.088 | **2929.951** | 3256.362 | 2955.530 | 3309.247 | 2959.752 |
| `sieve` | 1992.810 | **1483.975** | 1575.966 | 1535.018 | 1560.427 | 1545.003 |
| `fib` | 3198.825 | 2946.906 | 3266.936 | 2628.901 | 3217.616 | **2286.817** |
| `collatz` | 2156.333 | **2127.211** | 2152.305 | 2130.588 | 2153.673 | 2131.043 |
| `matmul` | 2944.649 | 2577.067 | 2382.037 | 1951.957 | 2052.228 | **1803.247** |
| `json_parse` | 1140.991 | 1181.314 | 480.888 | **440.373** | 870.985 | 871.900 |
| `nbody` | 3389.220 | 3915.305 | 3344.582 | 3342.752 | **3322.649** | 3584.155 |
| `chacha20` | 3746.073 | **3080.816** | 3587.551 | 3818.328 | 3562.440 | 3898.874 |
| `poly1305` | 8748.186 | 5836.805 | 8600.180 | **4495.364** | 10860.363 | 4653.697 |
| `blake2b` | **3990.188** | 4530.764 | 6260.577 | 6760.007 | 7548.541 | 8175.852 |
| `sha512` | 4539.456 | **4398.051** | 4693.153 | 4994.300 | 4777.309 | 5080.892 |
| `x25519` | 25158.906 | 12177.374 | 26444.632 | **11957.298** | 34758.447 | 11975.884 |

`nwasm` is faster than the reference runtime on 17 of 20 NURL modules,
16 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.562_ | _0.3_ | _2.1_ | _0.4_ | _0.1_ |
| `lcg` | 3274.640 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4093.845 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 3820.578 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3405.124 | 0.8 | 1.0 | 0.8 | 0.8 |
| `prefix_scan` | 550.543 | 0.7 | 0.3 | 1.0 | 0.7 |
| `binary_search` | 3963.320 | 0.8 | 1.6 | 0.8 | 0.9 |
| `sort_window` | 3450.028 | 1.0 | 1.5 | 1.1 | 1.1 |
| `bloom_filter` | 1092.693 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 2929.951 | 0.9 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1483.975 | 0.7 | 1.1 | 1.0 | 1.0 |
| `fib` | 2946.906 | 0.9 | 1.2 | 0.8 | 0.7 |
| `collatz` | 2127.211 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2577.067 | 0.9 | 0.8 | 0.8 | 0.9 |
| `json_parse` | 1181.314 | 1.0 | 2.5 | 0.9 | 1.0 |
| `nbody` | 3915.305 | 1.2 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3080.816 | 0.8 | 5.4 | 1.1 | 1.1 |
| `poly1305` | 5836.805 | 0.7 | 3.1 | 0.5 | 0.4 |
| `blake2b` | 4530.764 | 1.1 | 1.3 | 1.1 | 1.1 |
| `sha512` | 4398.051 | 1.0 | 1.2 | 1.1 | 1.1 |
| `x25519` | 12177.374 | 0.5 | 2.6 | 0.5 | 0.3 |

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
| `ring_write` | 17 | 26 | 16 | 915 | 4432 | 2124 |
| `histogram_bins` | 17 | 26 | 16 | 916 | 4432 | 2124 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4432 | 2124 |
| `binary_search` | 17 | 26 | 16 | 916 | 4433 | 2125 |
| `sort_window` | 17 | 27 | 16 | 917 | 4432 | 2125 |
| `bloom_filter` | 17 | 26 | 16 | 917 | 4432 | 2124 |
| `hash_join` | 25 | 28 | 16 | 924 | 4434 | 2127 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2124 |
| `fib` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `collatz` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `matmul` | 17 | 27 | 16 | 917 | 4432 | 2125 |
| `json_parse` | 49 | 53 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 17 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 57 | 48 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 28 | 35 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 36 | 43 | 16 | 925 | 4435 | 2127 |
| `sha512` | 36 | 40 | 16 | 922 | 4433 | 2126 |
| `x25519` | 44 | 43 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _316_ | _+7847 %_ | _9.214_ | _115.649_ | _+1155 %_ |
| `lcg` | 26 | 316 | +1107 % | 3293.489 | 3387.039 | +3 % |
| `packet_classifier` | 26 | 316 | +1110 % | 4452.228 | 4540.708 | +2 % |
| `ring_write` | 26 | 317 | +1107 % | 4385.336 | 4474.348 | +2 % |
| `histogram_bins` | 26 | 317 | +1104 % | 4256.920 | 4347.237 | +2 % |
| `prefix_scan` | 27 | 317 | +1091 % | 763.449 | 860.893 | +13 % |
| `binary_search` | 26 | 316 | +1102 % | 4751.584 | 4847.921 | +2 % |
| `sort_window` | 27 | 317 | +1093 % | 3538.060 | 3609.420 | +2 % |
| `bloom_filter` | 26 | 317 | +1098 % | 1336.841 | 1428.000 | +7 % |
| `hash_join` | 28 | 319 | +1028 % | 3267.088 | 3359.325 | +3 % |
| `sieve` | 26 | 317 | +1105 % | 1992.810 | 1725.380 | −13 % |
| `fib` | 26 | 316 | +1109 % | 3198.825 | 3459.319 | +8 % |
| `collatz` | 26 | 316 | +1111 % | 2156.333 | 2244.315 | +4 % |
| `matmul` | 27 | 317 | +1093 % | 2944.649 | 3028.923 | +3 % |
| `json_parse` | 53 | 337 | +541 % | 1140.991 | 1235.527 | +8 % |
| `nbody` | 28 | 318 | +1034 % | 3389.220 | 3482.761 | +3 % |
| `chacha20` | 48 | 364 | +656 % | 3746.073 | 3716.740 | −1 % |
| `poly1305` | 35 | 321 | +825 % | 8748.186 | 9317.355 | +7 % |
| `blake2b` | 43 | 329 | +671 % | 3990.188 | 4079.972 | +2 % |
| `sha512` | 40 | 327 | +720 % | 4539.456 | 4621.901 | +2 % |
| `x25519` | 43 | 330 | +668 % | 25158.906 | 25187.714 | +0 % |

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
| _(floor: empty program)_ | _3.696_ | _90.681_ | _43.831_ | _51.215_ | _35.746_ | _47.794_ | _55.992_ |
| `lcg` | 3.895 | 103.270 | 43.342 | 58.885 | 35.437 | 49.735 | 62.538 |
| `packet_classifier` | 3.872 | 105.096 | 44.640 | 59.910 | 35.071 | 50.854 | 61.764 |
| `ring_write` | 10.967 | 113.476 | 53.379 | 59.853 | 35.339 | 51.864 | 63.558 |
| `histogram_bins` | 11.033 | 115.239 | 54.088 | 61.760 | 35.088 | 53.387 | 63.276 |
| `prefix_scan` | 11.234 | 117.007 | 53.672 | 62.554 | 37.495 | 52.691 | 64.253 |
| `binary_search` | 11.134 | 115.221 | 53.606 | 59.845 | 35.149 | 54.901 | 65.993 |
| `sort_window` | 11.371 | 121.459 | 54.454 | 65.341 | 35.061 | 57.813 | 70.079 |
| `bloom_filter` | 11.649 | 119.730 | 55.505 | 64.571 | 34.855 | 55.751 | 66.216 |
| `hash_join` | 14.273 | 205.400 | 64.597 | 96.005 | 35.540 | 80.236 | 92.227 |
| `sieve` | 11.429 | 118.428 | 54.345 | 67.937 | 35.386 | 60.973 | 69.872 |
| `fib` | 3.945 | 104.010 | 43.891 | 59.634 | 35.230 | 51.450 | 62.961 |
| `collatz` | 4.117 | 106.555 | 43.875 | 59.526 | 35.394 | 50.615 | 62.703 |
| `matmul` | 12.267 | 122.010 | 57.988 | 68.170 | 35.595 | 65.865 | 76.543 |
| `json_parse` | 35.873 | 554.706 | 121.645 | 98.818 | 35.705 | 126.750 | 115.171 |
| `nbody` | 12.893 | 130.762 | 64.688 | 78.789 | 35.643 | 67.239 | 78.609 |
| `chacha20` | 35.834 | 610.049 | 135.240 | 89.029 | 35.172 | 82.002 | 91.765 |
| `poly1305` | 24.326 | 274.104 | 78.216 | 92.628 | 34.731 | 88.024 | 97.403 |
| `blake2b` | 28.704 | 422.238 | 88.837 | 92.063 | 34.886 | 93.016 | 99.624 |
| `sha512` | 28.403 | 368.845 | 94.937 | 81.464 | 35.096 | 82.158 | 90.540 |
| `x25519` | 30.518 | 400.696 | 106.623 | 592.759 | 35.844 | 486.559 | 498.210 |

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
