# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-27T17:37:35Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `5a5af96284881a4703e41b222ba1a114792be958` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40545456723 |
| NURL | `v0.79.0-6-g5a5af962` |
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
| _(floor: empty program)_ | _1.452_ | _14.395_ | _9.9_ | _1.505_ | _6.998_ | _4.6_ | _1.703_ | _32.960_ | _19.4_ |
| `lcg` | 3745.664 | 3766.655 | 1.0 | 3737.174 | 3762.159 | 1.0 | 3737.354 | 3773.736 | 1.0 |
| `packet_classifier` | 5465.128 | 5090.602 | 0.9 | 5451.395 | 5086.061 | 0.9 | 5455.481 | 5089.125 | 0.9 |
| `ring_write` | 4046.173 | 5017.954 | 1.2 | 4045.554 | 5007.564 | 1.2 | 4046.688 | 5017.101 | 1.2 |
| `histogram_bins` | 3941.887 | 4865.823 | 1.2 | 3942.715 | 4769.216 | 1.2 | 3738.519 | 4769.434 | 1.3 |
| `prefix_scan` | 2011.901 | 870.527 | 0.4 | 2008.169 | 890.081 | 0.4 | 2012.941 | 879.188 | 0.4 |
| `binary_search` | 3795.479 | 5724.649 | 1.5 | 3577.184 | 6000.042 | 1.7 | 4096.246 | 6011.407 | 1.5 |
| `sort_window` | 2554.927 | 4191.842 | 1.6 | 2554.040 | 2934.307 | 1.1 | 2491.631 | 3007.673 | 1.2 |
| `bloom_filter` | 1372.778 | 1534.313 | 1.1 | 1635.809 | 1584.839 | 1.0 | 1652.708 | 1490.265 | 0.9 |
| `hash_join` | 2629.933 | 4250.260 | 1.6 | 2811.300 | 4192.161 | 1.5 | 2805.899 | 4180.461 | 1.5 |
| `sieve` | 1607.589 | 2542.678 | 1.6 | 1800.745 | 1914.411 | 1.1 | 1779.619 | 2070.471 | 1.2 |
| `fib` | 2808.682 | 4076.397 | 1.5 | 2817.277 | 4079.846 | 1.4 | 2625.195 | 3785.468 | 1.4 |
| `collatz` | 1514.940 | 2501.510 | 1.7 | 1514.278 | 2491.875 | 1.6 | 1515.814 | 2497.257 | 1.6 |
| `matmul` | 3110.798 | 2924.177 | 0.9 | 3105.251 | 2512.009 | 0.8 | 3096.043 | 2347.048 | 0.8 |
| `json_parse` | 698.613 | 1443.502 | 2.1 | 684.106 | 613.910 | 0.9 | 973.557 | 1127.469 | 1.2 |
| `nbody` | 3899.970 | 4375.140 | 1.1 | 3901.539 | 3830.144 | 1.0 | 3699.130 | 3881.910 | 1.0 |
| `chacha20` | 572.885 | 3943.038 | 6.9 | 4048.723 | 4279.523 | 1.1 | 4178.175 | 4334.994 | 1.0 |
| `poly1305` | 974.946 | 11707.634 | 12.0 | 1939.024 | 11671.588 | 6.0 | 1937.814 | 15835.533 | 8.2 |
| `blake2b` | 4193.736 | 4683.833 | 1.1 | 6383.592 | 7113.045 | 1.1 | 6698.511 | 8873.946 | 1.3 |
| `sha512` | 4566.917 | 5344.996 | 1.2 | 4784.321 | 5694.186 | 1.2 | 5029.552 | 5874.989 | 1.2 |
| `x25519` | 4135.823 | 30614.825 | 7.4 | 5447.905 | 37021.704 | 6.8 | 5064.151 | 42529.291 | 8.4 |

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
| `histogram_bins` | 1.2 | 1.3 | 1.2 | 1.3 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 1.5 | 1.5 | 1.7 | 1.5 |
| `sort_window` | 1.6 | 1.5 | 1.1 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.6 | 1.5 | 1.5 | 1.5 |
| `sieve` | 1.6 | 1.6 | 1.1 | 1.1 |
| `fib` | 1.4 | 1.5 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.0 | 2.1 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 6.9 | 6.9 | 1.1 | 1.0 |
| `poly1305` | 12.0 | 12.0 | 6.0 | 8.2 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 7.4 | 7.4 | 6.8 | 8.4 |

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
| _(floor: empty program)_ | _14.395_ | _3.765_ | _6.998_ | _**3.189**_ | _32.960_ | _4.802_ |
| `lcg` | 3766.655 | **3738.548** | 3762.159 | 3743.048 | 3773.736 | 3745.566 |
| `packet_classifier` | 5090.602 | **4672.524** | 5086.061 | 4685.971 | 5089.125 | 4677.404 |
| `ring_write` | 5017.954 | **4362.718** | 5007.564 | 4364.764 | 5017.101 | 4365.180 |
| `histogram_bins` | 4865.823 | **3886.301** | 4769.216 | 4054.032 | 4769.434 | 4284.000 |
| `prefix_scan` | 870.527 | **629.179** | 890.081 | 820.461 | 879.188 | 634.313 |
| `binary_search` | 5724.649 | **4748.983** | 6000.042 | 4794.611 | 6011.407 | 5227.457 |
| `sort_window` | 4191.842 | 4429.122 | **2934.307** | 4270.209 | 3007.673 | 4047.669 |
| `bloom_filter` | 1534.313 | **1167.467** | 1584.839 | 1240.670 | 1490.265 | 1247.116 |
| `hash_join` | 4250.260 | 3677.666 | 4192.161 | **3674.293** | 4180.461 | 3694.956 |
| `sieve` | 2542.678 | **1719.794** | 1914.411 | 2045.985 | 2070.471 | 1792.447 |
| `fib` | 4076.397 | 3524.622 | 4079.846 | 3155.954 | 3785.468 | **2835.756** |
| `collatz` | 2501.510 | **2470.423** | 2491.875 | 2473.402 | 2497.257 | 2473.901 |
| `matmul` | 2924.177 | 2628.930 | 2512.009 | **2189.205** | 2347.048 | 2260.657 |
| `json_parse` | 1443.502 | 1699.917 | **613.910** | 646.953 | 1127.469 | 1373.977 |
| `nbody` | 4375.140 | 4209.330 | **3830.144** | 3866.635 | 3881.910 | 4391.357 |
| `chacha20` | 3943.038 | **3781.502** | 4279.523 | 4946.386 | 4334.994 | 5083.890 |
| `poly1305` | 11707.634 | 7060.478 | 11671.588 | 5496.694 | 15835.533 | **5438.389** |
| `blake2b` | **4683.833** | 5846.182 | 7113.045 | 8051.120 | 8873.946 | 10148.410 |
| `sha512` | **5344.996** | 6412.875 | 5694.186 | 5962.307 | 5874.989 | 5976.564 |
| `x25519` | 30614.825 | 15350.295 | 37021.704 | 15209.569 | 42529.291 | **15202.521** |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
13 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.765_ | _0.3_ | _2.6_ | _0.5_ | _0.1_ |
| `lcg` | 3738.548 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4672.524 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4362.718 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3886.301 | 0.8 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 629.179 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4748.983 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4429.122 | 1.1 | 1.7 | 1.5 | 1.3 |
| `bloom_filter` | 1167.467 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 3677.666 | 0.9 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1719.794 | 0.7 | 1.1 | 1.1 | 0.9 |
| `fib` | 3524.622 | 0.9 | 1.3 | 0.8 | 0.7 |
| `collatz` | 2470.423 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2628.930 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 1699.917 | 1.2 | 2.4 | 1.1 | 1.2 |
| `nbody` | 4209.330 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3781.502 | 1.0 | 6.6 | 1.2 | 1.2 |
| `poly1305` | 7060.478 | 0.6 | 7.2 | 0.5 | 0.3 |
| `blake2b` | 5846.182 | 1.2 | 1.4 | 1.1 | 1.1 |
| `sha512` | 6412.875 | 1.2 | 1.4 | 1.0 | 1.0 |
| `x25519` | 15350.295 | 0.5 | 3.7 | 0.4 | 0.4 |

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
| `ring_write` | 18 | 26 | 16 | 915 | 4432 | 2124 |
| `histogram_bins` | 18 | 26 | 16 | 916 | 4432 | 2124 |
| `prefix_scan` | 17 | 27 | 16 | 916 | 4432 | 2124 |
| `binary_search` | 17 | 26 | 16 | 916 | 4433 | 2125 |
| `sort_window` | 17 | 27 | 16 | 917 | 4432 | 2125 |
| `bloom_filter` | 18 | 26 | 16 | 917 | 4432 | 2124 |
| `hash_join` | 26 | 28 | 16 | 924 | 4434 | 2127 |
| `sieve` | 18 | 26 | 16 | 916 | 4431 | 2124 |
| `fib` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `collatz` | 17 | 26 | 16 | 915 | 4431 | 2124 |
| `matmul` | 18 | 27 | 16 | 917 | 4432 | 2125 |
| `json_parse` | 50 | 53 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 17 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 57 | 48 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 49 | 35 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 41 | 43 | 16 | 925 | 4435 | 2127 |
| `sha512` | 36 | 40 | 16 | 922 | 4433 | 2126 |
| `x25519` | 40 | 47 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _319_ | _+7922 %_ | _14.395_ | _155.378_ | _+979 %_ |
| `lcg` | 26 | 319 | +1118 % | 3766.655 | 3890.127 | +3 % |
| `packet_classifier` | 26 | 319 | +1121 % | 5090.602 | 5210.395 | +2 % |
| `ring_write` | 26 | 320 | +1119 % | 5017.954 | 5132.015 | +2 % |
| `histogram_bins` | 26 | 320 | +1116 % | 4865.823 | 5428.628 | +12 % |
| `prefix_scan` | 27 | 320 | +1102 % | 870.527 | 999.983 | +15 % |
| `binary_search` | 26 | 319 | +1114 % | 5724.649 | 5785.780 | +1 % |
| `sort_window` | 27 | 320 | +1104 % | 4191.842 | 4000.642 | −5 % |
| `bloom_filter` | 26 | 320 | +1109 % | 1534.313 | 1654.499 | +8 % |
| `hash_join` | 28 | 322 | +1038 % | 4250.260 | 4108.391 | −3 % |
| `sieve` | 26 | 320 | +1116 % | 2542.678 | 2653.557 | +4 % |
| `fib` | 26 | 319 | +1120 % | 4076.397 | 4232.030 | +4 % |
| `collatz` | 26 | 319 | +1122 % | 2501.510 | 2618.559 | +5 % |
| `matmul` | 27 | 320 | +1105 % | 2924.177 | 3028.363 | +4 % |
| `json_parse` | 53 | 340 | +546 % | 1443.502 | 1590.929 | +10 % |
| `nbody` | 28 | 321 | +1045 % | 4375.140 | 4495.797 | +3 % |
| `chacha20` | 48 | 365 | +662 % | 3943.038 | 4084.702 | +4 % |
| `poly1305` | 35 | 347 | +902 % | 11707.634 | 11881.699 | +1 % |
| `blake2b` | 43 | 332 | +678 % | 4683.833 | 4783.941 | +2 % |
| `sha512` | 40 | 329 | +727 % | 5344.996 | 5640.714 | +6 % |
| `x25519` | 47 | 339 | +614 % | 30614.825 | 30618.299 | +0 % |

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
| _(floor: empty program)_ | _4.497_ | _118.506_ | _52.890_ | _60.212_ | _43.014_ | _54.752_ | _68.135_ |
| `lcg` | 4.773 | 135.048 | 52.969 | 67.165 | 42.868 | 59.049 | 75.450 |
| `packet_classifier` | 4.689 | 135.793 | 52.302 | 69.357 | 42.288 | 58.586 | 73.682 |
| `ring_write` | 15.188 | 150.315 | 67.077 | 69.846 | 41.866 | 59.884 | 74.534 |
| `histogram_bins` | 16.036 | 160.253 | 68.556 | 75.754 | 43.019 | 65.056 | 77.349 |
| `prefix_scan` | 15.728 | 156.069 | 69.220 | 74.302 | 42.546 | 63.371 | 78.397 |
| `binary_search` | 16.220 | 159.222 | 69.030 | 73.131 | 43.085 | 68.559 | 82.283 |
| `sort_window` | 16.383 | 164.726 | 71.263 | 78.437 | 43.117 | 70.608 | 84.961 |
| `bloom_filter` | 17.097 | 168.101 | 73.008 | 80.087 | 43.929 | 68.091 | 83.747 |
| `hash_join` | 20.049 | 278.422 | 80.824 | 120.818 | 43.624 | 98.266 | 113.794 |
| `sieve` | 16.084 | 158.144 | 67.752 | 81.345 | 42.245 | 73.296 | 83.424 |
| `fib` | 4.804 | 138.229 | 53.012 | 69.583 | 43.421 | 60.421 | 74.878 |
| `collatz` | 4.872 | 140.048 | 53.611 | 69.296 | 42.835 | 59.928 | 75.039 |
| `matmul` | 17.503 | 164.328 | 71.909 | 84.380 | 43.324 | 81.220 | 94.163 |
| `json_parse` | 51.429 | 786.531 | 174.872 | 125.939 | 43.297 | 159.123 | 144.637 |
| `nbody` | 18.308 | 174.634 | 80.919 | 98.245 | 42.752 | 83.344 | 95.388 |
| `chacha20` | 59.376 | 863.424 | 209.715 | 113.626 | 43.460 | 101.347 | 115.193 |
| `poly1305` | 46.446 | 645.690 | 129.820 | 119.129 | 42.783 | 113.763 | 124.236 |
| `blake2b` | 39.130 | 571.178 | 120.365 | 112.726 | 44.769 | 113.115 | 124.712 |
| `sha512` | 40.045 | 504.406 | 124.192 | 100.734 | 42.952 | 99.497 | 115.388 |
| `x25519` | 39.679 | 1013.669 | 153.058 | 801.767 | 43.195 | 643.227 | 660.800 |

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
