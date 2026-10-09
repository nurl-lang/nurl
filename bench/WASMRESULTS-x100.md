# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-09T18:09:02Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `dd0104dbfa71691fddb49155e3ecaf66bf5e30c8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37966287339 |
| NURL | `v0.71.0-15-gdd0104db` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.5), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.4.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.467_ | _11.277_ | _7.7_ | _1.541_ | _6.959_ | _4.5_ | _1.672_ | _33.010_ | _19.7_ |
| `lcg` | 3733.264 | 3761.216 | 1.0 | 3734.462 | 3762.090 | 1.0 | 3735.505 | 3772.438 | 1.0 |
| `packet_classifier` | 5447.853 | 5090.772 | 0.9 | 5446.200 | 5083.488 | 0.9 | 5445.639 | 5088.519 | 0.9 |
| `ring_write` | 4056.913 | 5005.713 | 1.2 | 4047.788 | 5005.410 | 1.2 | 4045.813 | 5013.357 | 1.2 |
| `histogram_bins` | 3780.430 | 4909.899 | 1.3 | 3940.999 | 4758.814 | 1.2 | 3733.622 | 4763.999 | 1.3 |
| `prefix_scan` | 2010.555 | 871.524 | 0.4 | 2008.104 | 887.940 | 0.4 | 2014.992 | 877.062 | 0.4 |
| `binary_search` | 3570.336 | 5765.847 | 1.6 | 3574.229 | 6000.644 | 1.7 | 4089.323 | 6018.318 | 1.5 |
| `sort_window` | 2552.119 | 3907.627 | 1.5 | 2555.145 | 2927.419 | 1.1 | 2489.668 | 2998.692 | 1.2 |
| `bloom_filter` | 1372.406 | 1506.087 | 1.1 | 1635.002 | 1582.598 | 1.0 | 1650.224 | 1489.859 | 0.9 |
| `hash_join` | 2610.583 | 3622.303 | 1.4 | 2808.194 | 4191.498 | 1.5 | 2803.145 | 4182.254 | 1.5 |
| `sieve` | 1552.194 | 2288.940 | 1.5 | 1552.537 | 1812.287 | 1.2 | 1562.158 | 1833.247 | 1.2 |
| `fib` | 2342.181 | 4104.827 | 1.8 | 2823.377 | 4063.050 | 1.4 | 2626.887 | 3774.087 | 1.4 |
| `collatz` | 1514.698 | 2494.501 | 1.6 | 1513.285 | 2490.551 | 1.6 | 1515.762 | 2496.058 | 1.6 |
| `matmul` | 3107.096 | 2911.204 | 0.9 | 3114.157 | 2494.560 | 0.8 | 3102.313 | 2350.918 | 0.8 |
| `json_parse` | 724.324 | 1417.707 | 2.0 | 684.031 | 622.708 | 0.9 | 974.491 | 1130.093 | 1.2 |
| `nbody` | 3928.726 | 4376.307 | 1.1 | 3898.548 | 3832.417 | 1.0 | 3700.245 | 3885.415 | 1.1 |
| `chacha20` | 603.501 | 3785.160 | 6.3 | 3968.515 | 4268.588 | 1.1 | 4188.610 | 4306.463 | 1.0 |
| `poly1305` | 2181.190 | 12352.300 | 5.7 | 1938.795 | 11672.559 | 6.0 | 1938.133 | 13570.663 | 7.0 |
| `blake2b` | 4198.004 | 4669.882 | 1.1 | 6385.856 | 7129.246 | 1.1 | 6694.769 | 8866.425 | 1.3 |
| `sha512` | 4511.057 | 5345.897 | 1.2 | 4782.027 | 5703.437 | 1.2 | 5037.065 | 5886.731 | 1.2 |
| `x25519` | 5348.498 | 35430.932 | 6.6 | 5331.813 | 36953.655 | 6.9 | 5073.282 | 42566.610 | 8.4 |

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
| `histogram_bins` | 1.3 | 1.4 | 1.2 | 1.3 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 1.6 | 1.6 | 1.7 | 1.5 |
| `sort_window` | 1.5 | 1.5 | 1.1 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.4 | 1.4 | 1.5 | 1.5 |
| `sieve` | 1.5 | 1.6 | 1.2 | 1.2 |
| `fib` | 1.7 | 1.6 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 1.0 | 0.8 | 0.7 |
| `json_parse` | 1.9 | 2.0 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 6.3 | 6.3 | 1.1 | 1.0 |
| `poly1305` | 5.7 | 5.8 | 6.0 | 7.0 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 6.6 | 6.6 | 6.9 | 8.4 |

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
| _(floor: empty program)_ | _11.277_ | _3.670_ | _6.959_ | _**2.999**_ | _33.010_ | _4.228_ |
| `lcg` | 3761.216 | **3738.142** | 3762.090 | 3742.299 | 3772.438 | 3741.448 |
| `packet_classifier` | 5090.772 | **4671.708** | 5083.488 | 4674.117 | 5088.519 | 4674.799 |
| `ring_write` | 5005.713 | **4360.423** | 5005.410 | 4362.874 | 5013.357 | 4364.162 |
| `histogram_bins` | 4909.899 | **3885.026** | 4758.814 | 4053.248 | 4763.999 | 4281.324 |
| `prefix_scan` | 871.524 | **628.818** | 887.940 | 823.839 | 877.062 | 632.209 |
| `binary_search` | 5765.847 | **4696.509** | 6000.644 | 4794.279 | 6018.318 | 5176.721 |
| `sort_window` | 3907.627 | 4397.166 | **2927.419** | 4257.187 | 2998.692 | 4041.351 |
| `bloom_filter` | 1506.087 | **1163.522** | 1582.598 | 1233.696 | 1489.859 | 1240.875 |
| `hash_join` | **3622.303** | 3694.992 | 4191.498 | 3664.318 | 4182.254 | 3697.506 |
| `sieve` | 2288.940 | **1695.965** | 1812.287 | 1772.721 | 1833.247 | 1778.757 |
| `fib` | 4104.827 | 3512.113 | 4063.050 | 3155.086 | 3774.087 | **2845.511** |
| `collatz` | 2494.501 | **2468.868** | 2490.551 | 2472.409 | 2496.058 | 2472.655 |
| `matmul` | 2911.204 | 2624.194 | 2494.560 | **2189.253** | 2350.918 | 2248.787 |
| `json_parse` | 1417.707 | 1688.668 | **622.708** | 643.731 | 1130.093 | 1378.939 |
| `nbody` | 4376.307 | 4207.221 | **3832.417** | 3852.752 | 3885.415 | 4391.962 |
| `chacha20` | 3785.160 | **3744.617** | 4268.588 | 4940.521 | 4306.463 | 5084.807 |
| `poly1305` | 12352.300 | 7105.676 | 11672.559 | 5500.672 | 13570.663 | **5424.379** |
| `blake2b` | **4669.882** | 5861.763 | 7129.246 | 8113.997 | 8866.425 | 10077.115 |
| `sha512` | **5345.897** | 6412.928 | 5703.437 | 5955.551 | 5886.731 | 5986.744 |
| `x25519` | 35430.932 | **14980.630** | 36953.655 | 15012.897 | 42566.610 | 15061.758 |

`nwasm` is faster than the reference runtime on 15 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.670_ | _0.3_ | _2.5_ | _0.4_ | _0.1_ |
| `lcg` | 3738.142 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4671.708 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4360.423 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3885.026 | 0.8 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 628.818 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4696.509 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4397.166 | 1.1 | 1.7 | 1.5 | 1.3 |
| `bloom_filter` | 1163.522 | 0.8 | 0.8 | 0.8 | 0.8 |
| `hash_join` | 3694.992 | 1.0 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1695.965 | 0.7 | 1.1 | 1.0 | 1.0 |
| `fib` | 3512.113 | 0.9 | 1.5 | 0.8 | 0.8 |
| `collatz` | 2468.868 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2624.194 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 1688.668 | 1.2 | 2.3 | 1.0 | 1.2 |
| `nbody` | 4207.221 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3744.617 | 1.0 | 6.2 | 1.2 | 1.2 |
| `poly1305` | 7105.676 | 0.6 | 3.3 | 0.5 | 0.4 |
| `blake2b` | 5861.763 | 1.3 | 1.4 | 1.1 | 1.1 |
| `sha512` | 6412.928 | 1.2 | 1.4 | 1.0 | 1.0 |
| `x25519` | 14980.630 | 0.4 | 2.8 | 0.4 | 0.4 |

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
| `json_parse` | 49 | 52 | 16 | 1007 | 4445 | 2159 |
| `nbody` | 17 | 28 | 16 | 919 | 4432 | 2130 |
| `chacha20` | 48 | 48 | 16 | 923 | 4432 | 2129 |
| `poly1305` | 28 | 35 | 16 | 921 | 4432 | 2129 |
| `blake2b` | 36 | 42 | 16 | 925 | 4434 | 2132 |
| `sha512` | 32 | 40 | 16 | 922 | 4433 | 2130 |
| `x25519` | 44 | 43 | 48 | 1161 | 4464 | 2183 |

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
| _(floor: empty program)_ | _4_ | _312_ | _+7737 %_ | _11.277_ | _153.938_ | _+1265 %_ |
| `lcg` | 26 | 312 | +1090 % | 3761.216 | 3883.770 | +3 % |
| `packet_classifier` | 26 | 312 | +1093 % | 5090.772 | 5201.967 | +2 % |
| `ring_write` | 26 | 312 | +1090 % | 5005.713 | 5129.891 | +2 % |
| `histogram_bins` | 26 | 312 | +1088 % | 4909.899 | 5422.982 | +10 % |
| `prefix_scan` | 27 | 312 | +1074 % | 871.524 | 988.942 | +13 % |
| `binary_search` | 26 | 312 | +1085 % | 5765.847 | 5868.066 | +2 % |
| `sort_window` | 27 | 313 | +1076 % | 3907.627 | 3968.627 | +2 % |
| `bloom_filter` | 26 | 312 | +1081 % | 1506.087 | 1630.046 | +8 % |
| `hash_join` | 28 | 315 | +1012 % | 3622.303 | 3697.370 | +2 % |
| `sieve` | 26 | 312 | +1088 % | 2288.940 | 2596.615 | +13 % |
| `fib` | 26 | 312 | +1092 % | 4104.827 | 4000.133 | −3 % |
| `collatz` | 26 | 312 | +1094 % | 2494.501 | 2611.760 | +5 % |
| `matmul` | 27 | 312 | +1077 % | 2911.204 | 3122.097 | +7 % |
| `json_parse` | 52 | 332 | +534 % | 1417.707 | 1578.591 | +11 % |
| `nbody` | 28 | 314 | +1019 % | 4376.307 | 4480.838 | +2 % |
| `chacha20` | 48 | 359 | +646 % | 3785.160 | 3917.597 | +3 % |
| `poly1305` | 35 | 316 | +813 % | 12352.300 | 12876.930 | +4 % |
| `blake2b` | 42 | 325 | +679 % | 4669.882 | 4811.878 | +3 % |
| `sha512` | 40 | 322 | +709 % | 5345.897 | 5450.174 | +2 % |
| `x25519` | 43 | 326 | +656 % | 35430.932 | 35452.363 | +0 % |

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
| _(floor: empty program)_ | _3.799_ | _101.380_ | _52.801_ | _57.665_ | _42.991_ | _62.722_ | _74.373_ |
| `lcg` | 3.995 | 121.336 | 52.320 | 67.694 | 41.425 | 67.679 | 83.679 |
| `packet_classifier` | 4.157 | 124.181 | 52.850 | 68.889 | 44.456 | 69.527 | 82.410 |
| `ring_write` | 4.474 | 122.967 | 53.913 | 69.388 | 41.987 | 71.613 | 83.059 |
| `histogram_bins` | 4.324 | 121.218 | 50.854 | 68.037 | 39.940 | 70.612 | 82.655 |
| `prefix_scan` | 4.439 | 121.465 | 52.334 | 69.517 | 40.865 | 70.250 | 85.139 |
| `binary_search` | 4.723 | 121.025 | 53.257 | 67.307 | 40.623 | 73.073 | 86.410 |
| `sort_window` | 4.853 | 126.953 | 53.327 | 73.478 | 40.547 | 78.590 | 93.506 |
| `bloom_filter` | 5.336 | 125.987 | 54.416 | 73.736 | 40.377 | 74.948 | 84.971 |
| `hash_join` | 9.649 | 248.195 | 66.321 | 118.203 | 42.717 | 109.511 | 120.834 |
| `sieve` | 4.847 | 130.360 | 56.915 | 81.962 | 42.192 | 84.443 | 93.522 |
| `fib` | 4.254 | 122.548 | 53.518 | 69.715 | 42.196 | 69.831 | 82.972 |
| `collatz` | 4.206 | 119.178 | 50.922 | 67.801 | 41.076 | 67.974 | 81.829 |
| `matmul` | 6.180 | 130.847 | 54.575 | 81.285 | 40.966 | 88.687 | 99.561 |
| `json_parse` | 51.602 | 718.968 | 157.875 | 120.672 | 41.318 | 166.212 | 150.392 |
| `nbody` | 7.326 | 141.315 | 64.841 | 94.453 | 41.237 | 92.963 | 103.339 |
| `chacha20` | 55.631 | 706.892 | 178.863 | 107.307 | 40.846 | 107.210 | 120.049 |
| `poly1305` | 36.580 | 343.293 | 103.154 | 110.563 | 40.728 | 117.373 | 127.503 |
| `blake2b` | 38.455 | 497.982 | 111.357 | 113.217 | 40.229 | 125.097 | 133.727 |
| `sha512` | 38.211 | 461.624 | 120.053 | 97.674 | 41.475 | 108.815 | 118.159 |
| `x25519` | 47.483 | 521.603 | 144.528 | 783.688 | 42.653 | 648.227 | 663.029 |

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
