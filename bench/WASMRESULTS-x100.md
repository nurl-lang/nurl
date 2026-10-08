# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-08T10:03:05Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `f750a8857819e99191803b760307ce203da21196` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37754569976 |
| NURL | `v0.71.0-6-gf750a885` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.3), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.3.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.412_ | _10.657_ | _7.5_ | _1.480_ | _6.090_ | _4.1_ | _1.593_ | _33.444_ | _21.0_ |
| `lcg` | 3732.376 | 3759.483 | 1.0 | 3733.353 | 3759.779 | 1.0 | 3735.162 | 3766.430 | 1.0 |
| `packet_classifier` | 5446.104 | 5082.200 | 0.9 | 5445.010 | 5082.968 | 0.9 | 5444.951 | 5087.657 | 0.9 |
| `ring_write` | 4044.981 | 5002.829 | 1.2 | 4045.027 | 5005.681 | 1.2 | 4043.726 | 5010.466 | 1.2 |
| `histogram_bins` | 3778.288 | 5293.580 | 1.4 | 3941.481 | 4754.868 | 1.2 | 3732.179 | 4764.571 | 1.3 |
| `prefix_scan` | 2007.195 | 869.268 | 0.4 | 2007.970 | 890.615 | 0.4 | 2012.803 | 876.810 | 0.4 |
| `binary_search` | 3565.073 | 5728.624 | 1.6 | 3601.224 | 5997.547 | 1.7 | 4087.196 | 6015.777 | 1.5 |
| `sort_window` | 2552.521 | 3855.960 | 1.5 | 2552.500 | 2925.777 | 1.1 | 2489.862 | 2997.114 | 1.2 |
| `bloom_filter` | 1371.596 | 1505.458 | 1.1 | 1634.680 | 1581.403 | 1.0 | 1650.164 | 1487.023 | 0.9 |
| `hash_join` | 2613.418 | 3573.137 | 1.4 | 2812.091 | 4175.662 | 1.5 | 2808.051 | 4150.877 | 1.5 |
| `sieve` | 1532.260 | 1865.334 | 1.2 | 1532.337 | 1797.966 | 1.2 | 1531.312 | 1817.848 | 1.2 |
| `fib` | 2342.727 | 3877.538 | 1.7 | 2818.936 | 4088.527 | 1.5 | 2626.140 | 3767.430 | 1.4 |
| `collatz` | 1514.820 | 2493.304 | 1.6 | 1514.040 | 2491.463 | 1.6 | 1515.368 | 2495.676 | 1.6 |
| `matmul` | 3107.978 | 2906.334 | 0.9 | 3092.851 | 2505.249 | 0.8 | 3070.528 | 2339.127 | 0.8 |
| `json_parse` | 704.377 | 1508.168 | 2.1 | 685.745 | 607.955 | 0.9 | 970.082 | 1125.935 | 1.2 |
| `nbody` | 3907.948 | 4352.828 | 1.1 | 3898.580 | 3829.133 | 1.0 | 3701.893 | 3887.660 | 1.1 |
| `chacha20` | 1948.030 | 4478.189 | 2.3 | 3948.744 | 4268.531 | 1.1 | 4178.149 | 4325.683 | 1.0 |
| `poly1305` | 3899.910 | 24255.376 | 6.2 | 3729.881 | 26434.393 | 7.1 | 4222.685 | 29105.358 | 6.9 |
| `blake2b` | 24224.943 | 63519.007 | 2.6 | 6377.683 | 7119.274 | 1.1 | 6692.487 | 8866.123 | 1.3 |
| `sha512` | 4978.271 | 5726.508 | 1.2 | 4886.351 | 5719.254 | 1.2 | 5031.705 | 5856.574 | 1.2 |
| `x25519` | 5490.785 | 37918.106 | 6.9 | 5403.714 | 36909.981 | 6.8 | 5054.736 | 42414.749 | 8.4 |

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
| `histogram_bins` | 1.4 | 1.3 | 1.2 | 1.3 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 1.6 | 1.6 | 1.7 | 1.5 |
| `sort_window` | 1.5 | 1.5 | 1.1 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.4 | 1.4 | 1.5 | 1.5 |
| `sieve` | 1.2 | 1.2 | 1.2 | 1.2 |
| `fib` | 1.7 | 1.7 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.8 |
| `json_parse` | 2.1 | 2.3 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 2.3 | 2.3 | 1.1 | 1.0 |
| `poly1305` | 6.2 | 6.5 | 7.1 | 6.9 |
| `blake2b` | 2.6 | 2.6 | 1.1 | 1.3 |
| `sha512` | 1.1 | 1.2 | 1.2 | 1.2 |
| `x25519` | 6.9 | 6.9 | 6.8 | 8.4 |

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
| _(floor: empty program)_ | _10.657_ | _3.633_ | _6.090_ | _**3.162**_ | _33.444_ | _4.501_ |
| `lcg` | 3759.483 | **3736.445** | 3759.779 | 3739.978 | 3766.430 | 3739.450 |
| `packet_classifier` | 5082.200 | **4670.599** | 5082.968 | 4675.099 | 5087.657 | 4672.517 |
| `ring_write` | 5002.829 | **4358.173** | 5005.681 | 4361.177 | 5010.466 | 4361.813 |
| `histogram_bins` | 5293.580 | **3884.135** | 4754.868 | 4050.910 | 4764.571 | 4280.684 |
| `prefix_scan` | 869.268 | 632.695 | 890.615 | 822.632 | 876.810 | **632.222** |
| `binary_search` | 5728.624 | **4698.374** | 5997.547 | 4798.644 | 6015.777 | 5183.292 |
| `sort_window` | 3855.960 | 4391.550 | **2925.777** | 4279.757 | 2997.114 | 4040.687 |
| `bloom_filter` | 1505.458 | **1162.748** | 1581.403 | 1305.919 | 1487.023 | 1315.950 |
| `hash_join` | **3573.137** | 3637.681 | 4175.662 | 3709.370 | 4150.877 | 3770.036 |
| `sieve` | 1865.334 | **1688.323** | 1797.966 | 1764.896 | 1817.848 | 1759.300 |
| `fib` | 3877.538 | 3504.810 | 4088.527 | 3151.701 | 3767.430 | **2828.851** |
| `collatz` | 2493.304 | **2468.319** | 2491.463 | 2472.306 | 2495.676 | 2472.289 |
| `matmul` | 2906.334 | 2619.820 | 2505.249 | 2467.788 | 2339.127 | **2246.139** |
| `json_parse` | 1508.168 | 1877.635 | **607.955** | 658.880 | 1125.935 | 1411.295 |
| `nbody` | 4352.828 | 4315.867 | **3829.133** | 3856.582 | 3887.660 | 4392.131 |
| `chacha20` | 4478.189 | 7892.719 | **4268.531** | 8202.890 | 4325.683 | 8351.613 |
| `poly1305` | 24255.376 | 17397.134 | 26434.393 | **16692.611** | 29105.358 | 20085.507 |
| `blake2b` | 63519.007 | 47769.350 | **7119.274** | 13334.235 | 8866.123 | 15131.582 |
| `sha512` | 5726.508 | 5996.465 | **5719.254** | 6010.737 | 5856.574 | 6222.685 |
| `x25519` | 37918.106 | 26826.593 | 36909.981 | **26698.443** | 42414.749 | 30844.441 |

`nwasm` is faster than the reference runtime on 15 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.633_ | _0.3_ | _2.6_ | _0.5_ | _0.1_ |
| `lcg` | 3736.445 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4670.599 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4358.173 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3884.135 | 0.7 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 632.695 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4698.374 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4391.550 | 1.1 | 1.7 | 1.5 | 1.3 |
| `bloom_filter` | 1162.748 | 0.8 | 0.8 | 0.8 | 0.9 |
| `hash_join` | 3637.681 | 1.0 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1688.323 | 0.9 | 1.1 | 1.0 | 1.0 |
| `fib` | 3504.810 | 0.9 | 1.5 | 0.8 | 0.8 |
| `collatz` | 2468.319 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2619.820 | 0.9 | 0.8 | 1.0 | 1.0 |
| `json_parse` | 1877.635 | 1.2 | 2.7 | 1.1 | 1.3 |
| `nbody` | 4315.867 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 7892.719 | 1.8 | 4.1 | 1.9 | 1.9 |
| `poly1305` | 17397.134 | 0.7 | 4.5 | 0.6 | 0.7 |
| `blake2b` | 47769.350 | 0.8 | 2.0 | 1.9 | 1.7 |
| `sha512` | 5996.465 | 1.0 | 1.2 | 1.1 | 1.1 |
| `x25519` | 26826.593 | 0.7 | 4.9 | 0.7 | 0.7 |

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
| `lcg` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `packet_classifier` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `ring_write` | 17 | 26 | 16 | 915 | 4431 | 2128 |
| `histogram_bins` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4431 | 2129 |
| `binary_search` | 17 | 26 | 16 | 916 | 4432 | 2129 |
| `sort_window` | 17 | 27 | 16 | 917 | 4431 | 2129 |
| `bloom_filter` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `hash_join` | 25 | 28 | 16 | 924 | 4433 | 2131 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `fib` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `collatz` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `matmul` | 17 | 27 | 16 | 917 | 4432 | 2129 |
| `json_parse` | 41 | 50 | 16 | 1007 | 4445 | 2159 |
| `nbody` | 17 | 28 | 16 | 919 | 4432 | 2130 |
| `chacha20` | 31 | 46 | 16 | 923 | 4432 | 2129 |
| `poly1305` | 27 | 32 | 16 | 922 | 4433 | 2130 |
| `blake2b` | 32 | 38 | 16 | 925 | 4434 | 2132 |
| `sha512` | 31 | 37 | 16 | 922 | 4433 | 2130 |
| `x25519` | 35 | 42 | 48 | 1161 | 4464 | 2183 |

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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _10.657_ | _147.416_ | _+1283 %_ |
| `lcg` | 26 | 311 | +1087 % | 3759.483 | 3879.970 | +3 % |
| `packet_classifier` | 26 | 311 | +1090 % | 5082.200 | 5202.379 | +2 % |
| `ring_write` | 26 | 311 | +1087 % | 5002.829 | 5120.341 | +2 % |
| `histogram_bins` | 26 | 311 | +1084 % | 5293.580 | 5026.716 | −5 % |
| `prefix_scan` | 27 | 311 | +1071 % | 869.268 | 987.809 | +14 % |
| `binary_search` | 26 | 311 | +1082 % | 5728.624 | 5874.631 | +3 % |
| `sort_window` | 27 | 312 | +1073 % | 3855.960 | 4030.865 | +5 % |
| `bloom_filter` | 26 | 312 | +1078 % | 1505.458 | 1629.348 | +8 % |
| `hash_join` | 28 | 314 | +1009 % | 3573.137 | 3732.345 | +4 % |
| `sieve` | 26 | 311 | +1085 % | 1865.334 | 1985.470 | +6 % |
| `fib` | 26 | 311 | +1089 % | 3877.538 | 4213.915 | +9 % |
| `collatz` | 26 | 311 | +1091 % | 2493.304 | 2610.877 | +5 % |
| `matmul` | 27 | 311 | +1074 % | 2906.334 | 3027.149 | +4 % |
| `json_parse` | 50 | 331 | +561 % | 1508.168 | 1741.656 | +15 % |
| `nbody` | 28 | 313 | +1016 % | 4352.828 | 4485.235 | +3 % |
| `chacha20` | 46 | 331 | +621 % | 4478.189 | 4590.747 | +3 % |
| `poly1305` | 32 | 315 | +870 % | 24255.376 | 25426.185 | +5 % |
| `blake2b` | 38 | 322 | +743 % | 63519.007 | 63682.420 | +0 % |
| `sha512` | 37 | 320 | +768 % | 5726.508 | 5871.699 | +3 % |
| `x25519` | 42 | 326 | +681 % | 37918.106 | 38085.298 | +0 % |

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
| _(floor: empty program)_ | _3.343_ | _100.037_ | _49.628_ | _57.401_ | _41.223_ | _52.985_ | _67.057_ |
| `lcg` | 3.631 | 117.326 | 50.414 | 66.158 | 42.836 | 56.900 | 71.526 |
| `packet_classifier` | 3.728 | 117.377 | 50.741 | 66.623 | 40.371 | 57.521 | 71.395 |
| `ring_write` | 3.913 | 118.863 | 50.939 | 67.565 | 41.638 | 58.203 | 72.525 |
| `histogram_bins` | 3.962 | 121.634 | 51.007 | 70.481 | 40.312 | 60.062 | 73.803 |
| `prefix_scan` | 4.083 | 122.920 | 50.975 | 71.091 | 40.560 | 60.583 | 75.745 |
| `binary_search` | 4.451 | 122.476 | 51.865 | 68.847 | 41.014 | 62.843 | 76.926 |
| `sort_window` | 4.491 | 129.195 | 52.150 | 74.397 | 40.833 | 66.656 | 80.989 |
| `bloom_filter` | 4.986 | 128.971 | 54.166 | 74.779 | 40.570 | 63.312 | 78.002 |
| `hash_join` | 8.736 | 246.986 | 66.910 | 118.764 | 40.532 | 97.530 | 112.562 |
| `sieve` | 4.410 | 126.260 | 52.278 | 79.019 | 40.234 | 70.486 | 81.916 |
| `fib` | 3.866 | 118.667 | 50.549 | 67.047 | 40.548 | 58.169 | 72.010 |
| `collatz` | 3.977 | 120.303 | 50.719 | 68.222 | 40.658 | 58.574 | 72.124 |
| `matmul` | 5.689 | 130.287 | 54.103 | 80.501 | 41.138 | 77.848 | 88.550 |
| `json_parse` | 46.762 | 661.958 | 152.797 | 122.299 | 41.382 | 155.226 | 140.894 |
| `nbody` | 6.878 | 141.367 | 63.049 | 96.497 | 40.428 | 80.633 | 92.963 |
| `chacha20` | 38.283 | 440.831 | 146.536 | 108.866 | 40.225 | 96.438 | 109.338 |
| `poly1305` | 22.654 | 305.829 | 89.212 | 120.002 | 40.813 | 114.084 | 120.437 |
| `blake2b` | 36.363 | 393.377 | 125.784 | 111.714 | 40.008 | 111.395 | 119.527 |
| `sha512` | 32.191 | 379.765 | 111.262 | 96.656 | 40.530 | 97.100 | 108.606 |
| `x25519` | 38.771 | 469.986 | 133.401 | 781.815 | 41.693 | 630.822 | 647.755 |

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
