# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-21T15:13:31Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `790926410f4d90614deabfa032c40ee2a33e2306` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39617448550 |
| NURL | `v0.76.0-15-g79092641` |
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
| _(floor: empty program)_ | _1.547_ | _12.088_ | _7.8_ | _1.632_ | _8.571_ | _5.3_ | _1.754_ | _34.797_ | _19.8_ |
| `lcg` | 3736.264 | 3764.570 | 1.0 | 3739.543 | 3761.772 | 1.0 | 3739.729 | 3772.086 | 1.0 |
| `packet_classifier` | 5447.523 | 5087.184 | 0.9 | 5449.457 | 5086.774 | 0.9 | 5448.600 | 5094.594 | 0.9 |
| `ring_write` | 4045.603 | 5010.398 | 1.2 | 4044.649 | 5009.060 | 1.2 | 4046.866 | 5014.499 | 1.2 |
| `histogram_bins` | 3781.994 | 4870.728 | 1.3 | 3945.095 | 4767.133 | 1.2 | 3738.297 | 4768.927 | 1.3 |
| `prefix_scan` | 1994.311 | 870.191 | 0.4 | 2009.103 | 891.136 | 0.4 | 2012.986 | 886.178 | 0.4 |
| `binary_search` | 3736.153 | 5731.700 | 1.5 | 3566.263 | 6010.747 | 1.7 | 4093.498 | 6014.369 | 1.5 |
| `sort_window` | 2555.294 | 4176.095 | 1.6 | 2554.525 | 2929.341 | 1.1 | 2491.645 | 2998.731 | 1.2 |
| `bloom_filter` | 1416.468 | 1528.836 | 1.1 | 1636.504 | 1587.538 | 1.0 | 1652.940 | 1494.107 | 0.9 |
| `hash_join` | 2646.493 | 4246.472 | 1.6 | 2812.617 | 4198.791 | 1.5 | 2807.963 | 4156.902 | 1.5 |
| `sieve` | 1588.383 | 2368.445 | 1.5 | 1595.067 | 1864.900 | 1.2 | 1583.599 | 1917.600 | 1.2 |
| `fib` | 2815.282 | 4104.286 | 1.5 | 2819.416 | 4070.065 | 1.4 | 2627.114 | 3797.219 | 1.4 |
| `collatz` | 1516.083 | 2498.923 | 1.6 | 1515.024 | 2495.524 | 1.6 | 1517.199 | 2499.239 | 1.6 |
| `matmul` | 3097.820 | 2911.774 | 0.9 | 3101.539 | 2504.642 | 0.8 | 3095.345 | 2340.968 | 0.8 |
| `json_parse` | 684.358 | 1440.137 | 2.1 | 685.331 | 612.233 | 0.9 | 978.694 | 1130.655 | 1.2 |
| `nbody` | 3904.957 | 4381.406 | 1.1 | 3899.050 | 3832.612 | 1.0 | 3703.298 | 3888.047 | 1.0 |
| `chacha20` | 609.488 | 3944.608 | 6.5 | 3864.530 | 4300.841 | 1.1 | 4180.857 | 4313.709 | 1.0 |
| `poly1305` | 2181.465 | 12483.198 | 5.7 | 1941.387 | 11678.828 | 6.0 | 1939.841 | 13585.198 | 7.0 |
| `blake2b` | 4202.528 | 4658.878 | 1.1 | 6487.062 | 7131.836 | 1.1 | 6702.263 | 8887.241 | 1.3 |
| `sha512` | 4446.956 | 5348.282 | 1.2 | 4825.453 | 5691.029 | 1.2 | 5038.489 | 5872.334 | 1.2 |
| `x25519` | 5347.257 | 35493.147 | 6.6 | 5459.202 | 39529.792 | 7.2 | 5061.583 | 42495.037 | 8.4 |

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
| `binary_search` | 1.5 | 1.5 | 1.7 | 1.5 |
| `sort_window` | 1.6 | 1.6 | 1.1 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.6 | 1.6 | 1.5 | 1.5 |
| `sieve` | 1.5 | 1.2 | 1.2 | 1.2 |
| `fib` | 1.5 | 1.4 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.1 | 2.1 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 6.5 | 6.4 | 1.1 | 1.0 |
| `poly1305` | 5.7 | 5.8 | 6.0 | 7.0 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 6.6 | 6.6 | 7.2 | 8.4 |

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
| _(floor: empty program)_ | _12.088_ | _3.694_ | _8.571_ | _**3.244**_ | _34.797_ | _5.781_ |
| `lcg` | 3764.570 | **3741.342** | 3761.772 | 3742.678 | 3772.086 | 3743.736 |
| `packet_classifier` | 5087.184 | **4674.082** | 5086.774 | 4676.915 | 5094.594 | 4681.696 |
| `ring_write` | 5010.398 | **4364.026** | 5009.060 | 4365.720 | 5014.499 | 4369.988 |
| `histogram_bins` | 4870.728 | **3889.900** | 4767.133 | 4059.730 | 4768.927 | 4289.503 |
| `prefix_scan` | 870.191 | **640.201** | 891.136 | 821.800 | 886.178 | 640.901 |
| `binary_search` | 5731.700 | **4742.077** | 6010.747 | 4796.867 | 6014.369 | 5179.851 |
| `sort_window` | 4176.095 | 4441.947 | **2929.341** | 4254.067 | 2998.731 | 4044.323 |
| `bloom_filter` | 1528.836 | **1166.435** | 1587.538 | 1236.349 | 1494.107 | 1243.018 |
| `hash_join` | 4246.472 | 3678.928 | 4198.791 | **3671.208** | 4156.902 | 3716.956 |
| `sieve` | 2368.445 | **1755.557** | 1864.900 | 1840.470 | 1917.600 | 1844.219 |
| `fib` | 4104.286 | 3510.308 | 4070.065 | 3162.164 | 3797.219 | **2838.177** |
| `collatz` | 2498.923 | **2471.315** | 2495.524 | 2477.131 | 2499.239 | 2476.622 |
| `matmul` | 2911.774 | 2626.566 | 2504.642 | **2188.132** | 2340.968 | 2252.833 |
| `json_parse` | 1440.137 | 1700.406 | **612.233** | 641.669 | 1130.655 | 1364.851 |
| `nbody` | 4381.406 | 4354.330 | **3832.612** | 3859.969 | 3888.047 | 4397.427 |
| `chacha20` | 3944.608 | **3787.061** | 4300.841 | 4945.777 | 4313.709 | 5075.162 |
| `poly1305` | 12483.198 | 7098.915 | 11678.828 | 5491.792 | 13585.198 | **5429.661** |
| `blake2b` | **4658.878** | 5835.703 | 7131.836 | 8074.098 | 8887.241 | 10095.153 |
| `sha512` | **5348.282** | 6416.653 | 5691.029 | 5962.443 | 5872.334 | 5984.974 |
| `x25519` | 35493.147 | **15033.503** | 39529.792 | 15513.391 | 42495.037 | 15271.350 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.694_ | _0.3_ | _2.4_ | _0.4_ | _0.2_ |
| `lcg` | 3741.342 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4674.082 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4364.026 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3889.900 | 0.8 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 640.201 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4742.077 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4441.947 | 1.1 | 1.7 | 1.5 | 1.3 |
| `bloom_filter` | 1166.435 | 0.8 | 0.8 | 0.8 | 0.8 |
| `hash_join` | 3678.928 | 0.9 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1755.557 | 0.7 | 1.1 | 1.0 | 1.0 |
| `fib` | 3510.308 | 0.9 | 1.2 | 0.8 | 0.7 |
| `collatz` | 2471.315 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2626.566 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 1700.406 | 1.2 | 2.5 | 1.0 | 1.2 |
| `nbody` | 4354.330 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3787.061 | 1.0 | 6.2 | 1.1 | 1.2 |
| `poly1305` | 7098.915 | 0.6 | 3.3 | 0.5 | 0.4 |
| `blake2b` | 5835.703 | 1.3 | 1.4 | 1.1 | 1.1 |
| `sha512` | 6416.653 | 1.2 | 1.4 | 1.0 | 1.0 |
| `x25519` | 15033.503 | 0.4 | 2.8 | 0.4 | 0.4 |

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
| _(floor: empty program)_ | _4_ | _316_ | _+7847 %_ | _12.088_ | _153.894_ | _+1173 %_ |
| `lcg` | 26 | 316 | +1107 % | 3764.570 | 3885.421 | +3 % |
| `packet_classifier` | 26 | 316 | +1110 % | 5087.184 | 5210.530 | +2 % |
| `ring_write` | 26 | 317 | +1107 % | 5010.398 | 5133.726 | +2 % |
| `histogram_bins` | 26 | 317 | +1104 % | 4870.728 | 5001.477 | +3 % |
| `prefix_scan` | 27 | 317 | +1091 % | 870.191 | 997.613 | +15 % |
| `binary_search` | 26 | 316 | +1102 % | 5731.700 | 5857.843 | +2 % |
| `sort_window` | 27 | 317 | +1093 % | 4176.095 | 4325.169 | +4 % |
| `bloom_filter` | 26 | 317 | +1098 % | 1528.836 | 1649.871 | +8 % |
| `hash_join` | 28 | 319 | +1028 % | 4246.472 | 4368.883 | +3 % |
| `sieve` | 26 | 317 | +1105 % | 2368.445 | 2062.075 | −13 % |
| `fib` | 26 | 316 | +1109 % | 4104.286 | 4019.870 | −2 % |
| `collatz` | 26 | 316 | +1111 % | 2498.923 | 2619.604 | +5 % |
| `matmul` | 27 | 317 | +1093 % | 2911.774 | 3034.653 | +4 % |
| `json_parse` | 53 | 337 | +541 % | 1440.137 | 1608.510 | +12 % |
| `nbody` | 28 | 318 | +1034 % | 4381.406 | 4501.274 | +3 % |
| `chacha20` | 48 | 363 | +658 % | 3944.608 | 4066.252 | +3 % |
| `poly1305` | 35 | 321 | +825 % | 12483.198 | 12843.143 | +3 % |
| `blake2b` | 43 | 329 | +671 % | 4658.878 | 4774.852 | +2 % |
| `sha512` | 40 | 327 | +720 % | 5348.282 | 5463.391 | +2 % |
| `x25519` | 43 | 330 | +668 % | 35493.147 | 35595.303 | +0 % |

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
| _(floor: empty program)_ | _4.451_ | _112.758_ | _56.229_ | _63.434_ | _46.800_ | _67.255_ | _79.548_ |
| `lcg` | 4.580 | 130.040 | 57.293 | 73.118 | 44.591 | 73.244 | 87.184 |
| `packet_classifier` | 4.611 | 130.688 | 56.167 | 73.915 | 43.875 | 75.599 | 88.399 |
| `ring_write` | 13.903 | 145.612 | 68.322 | 75.834 | 45.229 | 77.042 | 90.404 |
| `histogram_bins` | 14.162 | 148.003 | 69.672 | 76.824 | 44.684 | 77.752 | 90.368 |
| `prefix_scan` | 14.096 | 149.856 | 70.907 | 79.639 | 43.456 | 78.649 | 91.407 |
| `binary_search` | 14.146 | 148.009 | 70.051 | 75.511 | 44.297 | 82.131 | 94.646 |
| `sort_window` | 14.428 | 156.578 | 72.465 | 83.431 | 44.994 | 86.138 | 98.704 |
| `bloom_filter` | 15.132 | 161.059 | 77.763 | 89.317 | 46.213 | 83.582 | 97.042 |
| `hash_join` | 18.227 | 275.763 | 85.029 | 126.160 | 44.969 | 117.706 | 131.090 |
| `sieve` | 14.389 | 150.160 | 72.098 | 86.204 | 45.786 | 96.486 | 101.866 |
| `fib` | 4.856 | 132.726 | 57.130 | 73.692 | 44.443 | 75.245 | 89.338 |
| `collatz` | 5.066 | 137.226 | 57.974 | 75.061 | 44.515 | 78.168 | 87.810 |
| `matmul` | 15.803 | 159.584 | 74.688 | 88.083 | 45.944 | 98.950 | 109.277 |
| `json_parse` | 47.267 | 759.674 | 176.255 | 129.024 | 45.389 | 179.904 | 164.574 |
| `nbody` | 17.225 | 170.018 | 86.987 | 104.448 | 47.038 | 99.939 | 113.894 |
| `chacha20` | 49.304 | 844.212 | 182.775 | 118.082 | 45.699 | 121.358 | 131.388 |
| `poly1305` | 33.247 | 369.754 | 107.150 | 121.454 | 47.094 | 131.048 | 141.987 |
| `blake2b` | 37.709 | 569.997 | 119.318 | 120.038 | 45.431 | 136.021 | 141.560 |
| `sha512` | 36.410 | 491.618 | 126.127 | 105.812 | 44.523 | 118.003 | 129.847 |
| `x25519` | 41.473 | 537.973 | 142.403 | 802.144 | 45.438 | 664.818 | 700.816 |

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
