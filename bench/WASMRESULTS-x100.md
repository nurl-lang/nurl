# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-28T05:16:00Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16373444 KiB |
| Commit | `da5aacbfbb307d0a1aa4f502394df0c540a1c400` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40632993913 |
| NURL | `v0.79.1-12-gda5aacbf` |
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
| _(floor: empty program)_ | _1.482_ | _13.441_ | _9.1_ | _1.541_ | _6.684_ | _4.3_ | _1.687_ | _33.832_ | _20.1_ |
| `lcg` | 3734.587 | 3761.512 | 1.0 | 3732.885 | 3759.719 | 1.0 | 3734.343 | 3770.193 | 1.0 |
| `packet_classifier` | 5447.009 | 5086.438 | 0.9 | 5444.976 | 5095.584 | 0.9 | 5444.812 | 5089.174 | 0.9 |
| `ring_write` | 4046.035 | 5007.010 | 1.2 | 4045.883 | 5006.145 | 1.2 | 4046.066 | 5011.504 | 1.2 |
| `histogram_bins` | 3941.869 | 4880.673 | 1.2 | 3943.216 | 4760.027 | 1.2 | 3734.789 | 4768.787 | 1.3 |
| `prefix_scan` | 2008.635 | 876.725 | 0.4 | 2006.445 | 886.669 | 0.4 | 2013.092 | 875.879 | 0.4 |
| `binary_search` | 3781.145 | 5729.936 | 1.5 | 3589.226 | 5995.491 | 1.7 | 4085.979 | 6010.710 | 1.5 |
| `sort_window` | 2553.104 | 4183.284 | 1.6 | 2553.513 | 2932.041 | 1.1 | 2491.501 | 3003.749 | 1.2 |
| `bloom_filter` | 1372.489 | 1533.865 | 1.1 | 1634.756 | 1583.574 | 1.0 | 1650.005 | 1493.443 | 0.9 |
| `hash_join` | 2629.575 | 4236.522 | 1.6 | 2815.959 | 4178.809 | 1.5 | 2823.005 | 4154.125 | 1.5 |
| `sieve` | 1774.984 | 2481.156 | 1.4 | 1736.650 | 2005.664 | 1.2 | 1766.910 | 2017.656 | 1.1 |
| `fib` | 2806.497 | 4096.701 | 1.5 | 2816.364 | 4068.348 | 1.4 | 2625.433 | 3777.104 | 1.4 |
| `collatz` | 1515.119 | 2493.561 | 1.6 | 1513.640 | 2491.948 | 1.6 | 1515.765 | 2495.139 | 1.6 |
| `matmul` | 3102.550 | 2901.481 | 0.9 | 3091.809 | 2507.108 | 0.8 | 3107.556 | 2333.899 | 0.8 |
| `json_parse` | 696.696 | 1457.171 | 2.1 | 690.508 | 626.858 | 0.9 | 980.102 | 1127.509 | 1.2 |
| `nbody` | 3905.412 | 4378.443 | 1.1 | 3898.489 | 3836.768 | 1.0 | 3699.695 | 3888.545 | 1.1 |
| `chacha20` | 573.597 | 3946.083 | 6.9 | 4061.568 | 4280.762 | 1.1 | 4176.515 | 4315.419 | 1.0 |
| `poly1305` | 961.794 | 11703.764 | 12.2 | 1939.152 | 11681.419 | 6.0 | 1937.718 | 13760.226 | 7.1 |
| `blake2b` | 4194.278 | 4657.444 | 1.1 | 6375.951 | 7113.378 | 1.1 | 6733.042 | 8888.527 | 1.3 |
| `sha512` | 4552.617 | 5366.503 | 1.2 | 4792.100 | 5695.943 | 1.2 | 5030.390 | 5860.641 | 1.2 |
| `x25519` | 4135.542 | 31656.787 | 7.7 | 5367.124 | 36989.421 | 6.9 | 5057.945 | 42464.379 | 8.4 |

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
| `sieve` | 1.4 | 1.4 | 1.2 | 1.1 |
| `fib` | 1.5 | 1.5 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.1 | 2.1 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 6.9 | 6.8 | 1.1 | 1.0 |
| `poly1305` | 12.2 | 12.2 | 6.0 | 7.1 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 7.7 | 7.4 | 6.9 | 8.4 |

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
| _(floor: empty program)_ | _13.441_ | _3.708_ | _6.684_ | _**3.141**_ | _33.832_ | _4.488_ |
| `lcg` | 3761.512 | **3739.222** | 3759.719 | 3742.003 | 3770.193 | 3740.823 |
| `packet_classifier` | 5086.438 | **4671.994** | 5095.584 | 4674.195 | 5089.174 | 4674.506 |
| `ring_write` | 5007.010 | **4359.056** | 5006.145 | 4363.913 | 5011.504 | 4366.452 |
| `histogram_bins` | 4880.673 | **3891.015** | 4760.027 | 4055.520 | 4768.787 | 4283.082 |
| `prefix_scan` | 876.725 | **629.174** | 886.669 | 819.649 | 875.879 | 633.122 |
| `binary_search` | 5729.936 | **4744.321** | 5995.491 | 4792.169 | 6010.710 | 5177.580 |
| `sort_window` | 4183.284 | 4427.542 | **2932.041** | 4271.743 | 3003.749 | 4045.411 |
| `bloom_filter` | 1533.865 | **1163.475** | 1583.574 | 1233.563 | 1493.443 | 1243.000 |
| `hash_join` | 4236.522 | 3692.141 | 4178.809 | **3661.635** | 4154.125 | 3706.009 |
| `sieve` | 2481.156 | **1891.431** | 2005.664 | 1984.139 | 2017.656 | 1975.869 |
| `fib` | 4096.701 | 3520.120 | 4068.348 | 3160.965 | 3777.104 | **2828.895** |
| `collatz` | 2493.561 | **2468.429** | 2491.948 | 2473.200 | 2495.139 | 2472.823 |
| `matmul` | 2901.481 | 2626.508 | 2507.108 | **2185.637** | 2333.899 | 2253.760 |
| `json_parse` | 1457.171 | 1709.313 | **626.858** | 643.310 | 1127.509 | 1371.541 |
| `nbody` | 4378.443 | 4205.724 | **3836.768** | 3860.189 | 3888.545 | 4391.754 |
| `chacha20` | 3946.083 | **3786.994** | 4280.762 | 4942.850 | 4315.419 | 5077.820 |
| `poly1305` | 11703.764 | 7047.112 | 11681.419 | 5491.053 | 13760.226 | **5430.047** |
| `blake2b` | **4657.444** | 5841.648 | 7113.378 | 8112.013 | 8888.527 | 10191.939 |
| `sha512` | **5366.503** | 6414.445 | 5695.943 | 5956.479 | 5860.641 | 5987.507 |
| `x25519` | 31656.787 | 15454.305 | 36989.421 | **15092.188** | 42464.379 | 15239.215 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.708_ | _0.3_ | _2.5_ | _0.5_ | _0.1_ |
| `lcg` | 3739.222 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4671.994 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4359.056 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3891.015 | 0.8 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 629.174 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4744.321 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4427.542 | 1.1 | 1.7 | 1.5 | 1.3 |
| `bloom_filter` | 1163.475 | 0.8 | 0.8 | 0.8 | 0.8 |
| `hash_join` | 3692.141 | 0.9 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1891.431 | 0.8 | 1.1 | 1.0 | 1.0 |
| `fib` | 3520.120 | 0.9 | 1.3 | 0.8 | 0.7 |
| `collatz` | 2468.429 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2626.508 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 1709.313 | 1.2 | 2.5 | 1.0 | 1.2 |
| `nbody` | 4205.724 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3786.994 | 1.0 | 6.6 | 1.2 | 1.2 |
| `poly1305` | 7047.112 | 0.6 | 7.3 | 0.5 | 0.4 |
| `blake2b` | 5841.648 | 1.3 | 1.4 | 1.1 | 1.1 |
| `sha512` | 6414.445 | 1.2 | 1.4 | 1.0 | 1.0 |
| `x25519` | 15454.305 | 0.5 | 3.7 | 0.4 | 0.4 |

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
| `blake2b` | 40 | 43 | 16 | 925 | 4435 | 2127 |
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
| _(floor: empty program)_ | _4_ | _319_ | _+7928 %_ | _13.441_ | _156.439_ | _+1064 %_ |
| `lcg` | 26 | 320 | +1119 % | 3761.512 | 3887.816 | +3 % |
| `packet_classifier` | 26 | 320 | +1122 % | 5086.438 | 5205.220 | +2 % |
| `ring_write` | 26 | 320 | +1119 % | 5007.010 | 5128.672 | +2 % |
| `histogram_bins` | 26 | 320 | +1117 % | 4880.673 | 5424.884 | +11 % |
| `prefix_scan` | 27 | 320 | +1103 % | 876.725 | 1002.524 | +14 % |
| `binary_search` | 26 | 320 | +1115 % | 5729.936 | 5784.817 | +1 % |
| `sort_window` | 27 | 320 | +1105 % | 4183.284 | 3989.710 | −5 % |
| `bloom_filter` | 26 | 320 | +1110 % | 1533.865 | 1651.816 | +8 % |
| `hash_join` | 28 | 323 | +1039 % | 4236.522 | 4131.944 | −2 % |
| `sieve` | 26 | 320 | +1117 % | 2481.156 | 2618.862 | +6 % |
| `fib` | 26 | 320 | +1121 % | 4096.701 | 4263.492 | +4 % |
| `collatz` | 26 | 320 | +1123 % | 2493.561 | 2615.303 | +5 % |
| `matmul` | 27 | 320 | +1106 % | 2901.481 | 3038.186 | +5 % |
| `json_parse` | 53 | 340 | +547 % | 1457.171 | 1605.698 | +10 % |
| `nbody` | 28 | 321 | +1046 % | 4378.443 | 4499.956 | +3 % |
| `chacha20` | 48 | 366 | +662 % | 3946.083 | 4068.762 | +3 % |
| `poly1305` | 35 | 347 | +902 % | 11703.764 | 11895.397 | +2 % |
| `blake2b` | 43 | 332 | +678 % | 4657.444 | 4773.978 | +3 % |
| `sha512` | 40 | 330 | +728 % | 5366.503 | 5486.643 | +2 % |
| `x25519` | 47 | 339 | +615 % | 31656.787 | 30554.110 | −3 % |

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
| _(floor: empty program)_ | _4.388_ | _117.522_ | _51.738_ | _57.464_ | _42.522_ | _53.181_ | _67.905_ |
| `lcg` | 4.592 | 134.952 | 52.589 | 67.025 | 42.287 | 57.578 | 71.624 |
| `packet_classifier` | 4.749 | 137.303 | 52.823 | 69.868 | 41.994 | 58.782 | 73.068 |
| `ring_write` | 14.963 | 147.807 | 65.772 | 68.369 | 41.417 | 59.435 | 73.728 |
| `histogram_bins` | 15.342 | 149.637 | 66.405 | 69.170 | 42.458 | 61.137 | 75.394 |
| `prefix_scan` | 15.183 | 151.815 | 68.835 | 72.713 | 42.963 | 61.771 | 76.016 |
| `binary_search` | 15.414 | 151.254 | 66.389 | 68.764 | 42.061 | 63.319 | 77.725 |
| `sort_window` | 15.851 | 160.071 | 77.142 | 75.768 | 41.876 | 68.519 | 81.681 |
| `bloom_filter` | 16.067 | 154.088 | 70.107 | 75.018 | 41.540 | 64.208 | 78.916 |
| `hash_join` | 19.391 | 272.605 | 86.099 | 119.541 | 41.001 | 97.230 | 111.557 |
| `sieve` | 15.314 | 151.928 | 68.081 | 80.284 | 42.161 | 69.595 | 81.638 |
| `fib` | 4.735 | 132.733 | 50.711 | 67.355 | 40.592 | 58.261 | 72.540 |
| `collatz` | 4.860 | 135.446 | 51.840 | 68.044 | 41.589 | 58.573 | 72.230 |
| `matmul` | 16.858 | 160.035 | 70.911 | 81.998 | 41.848 | 78.627 | 90.070 |
| `json_parse` | 50.240 | 760.120 | 178.525 | 123.352 | 42.242 | 155.292 | 139.879 |
| `nbody` | 17.870 | 170.567 | 80.015 | 96.457 | 41.458 | 79.859 | 94.281 |
| `chacha20` | 59.457 | 857.189 | 188.894 | 111.145 | 42.664 | 99.369 | 112.857 |
| `poly1305` | 45.273 | 629.442 | 128.852 | 114.768 | 42.201 | 108.301 | 122.475 |
| `blake2b` | 40.984 | 579.060 | 116.694 | 116.188 | 42.362 | 115.563 | 124.924 |
| `sha512` | 40.153 | 505.221 | 130.282 | 100.714 | 42.711 | 100.015 | 109.893 |
| `x25519` | 39.478 | 1016.647 | 125.032 | 788.049 | 41.808 | 624.915 | 649.720 |

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
