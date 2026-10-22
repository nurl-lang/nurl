# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-22T06:40:55Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `44aff7b99d90d5a516484902b2122b73eeb720b2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39731091483 |
| NURL | `v0.76.0-31-g44aff7b9` |
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
| _(floor: empty program)_ | _1.571_ | _11.607_ | _7.4_ | _1.648_ | _7.525_ | _4.6_ | _1.825_ | _33.440_ | _18.3_ |
| `lcg` | 3737.459 | 3764.840 | 1.0 | 3738.164 | 3771.555 | 1.0 | 3737.561 | 3772.655 | 1.0 |
| `packet_classifier` | 5450.132 | 5088.101 | 0.9 | 5449.133 | 5086.550 | 0.9 | 5450.091 | 5095.867 | 0.9 |
| `ring_write` | 4066.961 | 5008.392 | 1.2 | 4054.214 | 5011.121 | 1.2 | 4049.068 | 5017.189 | 1.2 |
| `histogram_bins` | 3944.095 | 4863.101 | 1.2 | 3943.666 | 4761.775 | 1.2 | 3736.575 | 4769.837 | 1.3 |
| `prefix_scan` | 2011.548 | 875.726 | 0.4 | 2011.098 | 889.745 | 0.4 | 2014.501 | 879.931 | 0.4 |
| `binary_search` | 3792.186 | 5735.291 | 1.5 | 3573.490 | 6007.786 | 1.7 | 4124.522 | 6024.513 | 1.5 |
| `sort_window` | 2555.387 | 4172.611 | 1.6 | 2558.805 | 2931.329 | 1.1 | 2493.388 | 3002.391 | 1.2 |
| `bloom_filter` | 1373.687 | 1536.984 | 1.1 | 1636.717 | 1595.500 | 1.0 | 1651.610 | 1490.537 | 0.9 |
| `hash_join` | 2632.079 | 4244.371 | 1.6 | 2811.439 | 4199.650 | 1.5 | 2814.329 | 4180.680 | 1.5 |
| `sieve` | 1585.060 | 2542.947 | 1.6 | 1816.182 | 2076.874 | 1.1 | 1817.189 | 2099.310 | 1.2 |
| `fib` | 2812.811 | 4130.289 | 1.5 | 2818.901 | 4089.244 | 1.5 | 2628.978 | 3788.462 | 1.4 |
| `collatz` | 1515.618 | 2495.242 | 1.6 | 1515.506 | 2494.522 | 1.6 | 1516.454 | 2498.007 | 1.6 |
| `matmul` | 3108.854 | 2918.376 | 0.9 | 3120.164 | 2518.320 | 0.8 | 3106.940 | 2345.904 | 0.8 |
| `json_parse` | 693.806 | 1438.500 | 2.1 | 685.135 | 618.992 | 0.9 | 971.622 | 1126.875 | 1.2 |
| `nbody` | 4154.759 | 4395.166 | 1.1 | 3900.596 | 3833.283 | 1.0 | 3702.194 | 3890.329 | 1.1 |
| `chacha20` | 600.890 | 3958.157 | 6.6 | 4058.794 | 4302.780 | 1.1 | 4198.442 | 4311.568 | 1.0 |
| `poly1305` | 2182.252 | 12479.814 | 5.7 | 1939.263 | 11711.038 | 6.0 | 1940.204 | 13594.858 | 7.0 |
| `blake2b` | 4218.446 | 4645.939 | 1.1 | 6530.773 | 7140.765 | 1.1 | 7559.468 | 8884.840 | 1.2 |
| `sha512` | 4547.970 | 5350.392 | 1.2 | 4854.715 | 5693.012 | 1.2 | 5025.906 | 5882.599 | 1.2 |
| `x25519` | 4229.869 | 35255.764 | 8.3 | 5437.234 | 36946.101 | 6.8 | 5053.367 | 42519.252 | 8.4 |

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
| `sieve` | 1.6 | 1.5 | 1.1 | 1.1 |
| `fib` | 1.5 | 1.5 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.1 | 2.1 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.0 | 1.0 | 1.0 |
| `chacha20` | 6.6 | 6.5 | 1.1 | 1.0 |
| `poly1305` | 5.7 | 5.7 | 6.0 | 7.0 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.2 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 8.3 | 8.3 | 6.8 | 8.4 |

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
| _(floor: empty program)_ | _11.607_ | _3.803_ | _7.525_ | _**3.356**_ | _33.440_ | _5.344_ |
| `lcg` | 3764.840 | **3741.923** | 3771.555 | 3745.195 | 3772.655 | 3747.195 |
| `packet_classifier` | 5088.101 | **4673.399** | 5086.550 | 4679.448 | 5095.867 | 4679.983 |
| `ring_write` | 5008.392 | **4363.566** | 5011.121 | 4368.032 | 5017.189 | 4370.918 |
| `histogram_bins` | 4863.101 | **3889.630** | 4761.775 | 4056.259 | 4769.837 | 4285.443 |
| `prefix_scan` | 875.726 | **632.454** | 889.745 | 820.318 | 879.931 | 634.557 |
| `binary_search` | 5735.291 | **4743.149** | 6007.786 | 4795.042 | 6024.513 | 5190.474 |
| `sort_window` | 4172.611 | 4434.165 | **2931.329** | 4245.827 | 3002.391 | 4045.482 |
| `bloom_filter` | 1536.984 | **1173.110** | 1595.500 | 1237.417 | 1490.537 | 1242.311 |
| `hash_join` | 4244.371 | 3679.694 | 4199.650 | **3673.024** | 4180.680 | 3701.727 |
| `sieve` | 2542.947 | **1763.939** | 2076.874 | 1829.688 | 2099.310 | 1826.521 |
| `fib` | 4130.289 | 3530.704 | 4089.244 | 3157.970 | 3788.462 | **2831.975** |
| `collatz` | 2495.242 | **2472.704** | 2494.522 | 2475.523 | 2498.007 | 2475.324 |
| `matmul` | 2918.376 | 2625.371 | 2518.320 | **2194.055** | 2345.904 | 2256.680 |
| `json_parse` | 1438.500 | 1698.334 | **618.992** | 640.972 | 1126.875 | 1376.526 |
| `nbody` | 4395.166 | 4216.203 | **3833.283** | 3856.881 | 3890.329 | 4398.842 |
| `chacha20` | 3958.157 | **3786.056** | 4302.780 | 4943.452 | 4311.568 | 5087.370 |
| `poly1305` | 12479.814 | 7096.608 | 11711.038 | 5510.907 | 13594.858 | **5422.811** |
| `blake2b` | **4645.939** | 5837.246 | 7140.765 | 8052.222 | 8884.840 | 10098.141 |
| `sha512` | **5350.392** | 6411.084 | 5693.012 | 5967.487 | 5882.599 | 5995.887 |
| `x25519` | 35255.764 | **13816.733** | 36946.101 | 15704.862 | 42519.252 | 15237.555 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.803_ | _0.3_ | _2.4_ | _0.4_ | _0.2_ |
| `lcg` | 3741.923 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4673.399 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4363.566 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3889.630 | 0.8 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 632.454 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4743.149 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4434.165 | 1.1 | 1.7 | 1.4 | 1.3 |
| `bloom_filter` | 1173.110 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 3679.694 | 0.9 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1763.939 | 0.7 | 1.1 | 0.9 | 0.9 |
| `fib` | 3530.704 | 0.9 | 1.3 | 0.8 | 0.7 |
| `collatz` | 2472.704 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2625.371 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 1698.334 | 1.2 | 2.4 | 1.0 | 1.2 |
| `nbody` | 4216.203 | 1.0 | 1.0 | 1.0 | 1.1 |
| `chacha20` | 3786.056 | 1.0 | 6.3 | 1.1 | 1.2 |
| `poly1305` | 7096.608 | 0.6 | 3.3 | 0.5 | 0.4 |
| `blake2b` | 5837.246 | 1.3 | 1.4 | 1.1 | 1.1 |
| `sha512` | 6411.084 | 1.2 | 1.4 | 1.0 | 1.0 |
| `x25519` | 13816.733 | 0.4 | 3.3 | 0.4 | 0.4 |

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
| `poly1305` | 28 | 35 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 41 | 43 | 16 | 925 | 4435 | 2127 |
| `sha512` | 36 | 40 | 16 | 922 | 4433 | 2126 |
| `x25519` | 40 | 49 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _317_ | _+7866 %_ | _11.607_ | _157.114_ | _+1254 %_ |
| `lcg` | 26 | 317 | +1110 % | 3764.840 | 3890.474 | +3 % |
| `packet_classifier` | 26 | 317 | +1113 % | 5088.101 | 5216.623 | +3 % |
| `ring_write` | 26 | 317 | +1110 % | 5008.392 | 5132.365 | +2 % |
| `histogram_bins` | 26 | 317 | +1107 % | 4863.101 | 5435.742 | +12 % |
| `prefix_scan` | 27 | 318 | +1094 % | 875.726 | 1000.468 | +14 % |
| `binary_search` | 26 | 317 | +1105 % | 5735.291 | 5785.210 | +1 % |
| `sort_window` | 27 | 318 | +1095 % | 4172.611 | 4002.685 | −4 % |
| `bloom_filter` | 26 | 318 | +1101 % | 1536.984 | 1653.947 | +8 % |
| `hash_join` | 28 | 320 | +1030 % | 4244.371 | 4117.890 | −3 % |
| `sieve` | 26 | 317 | +1108 % | 2542.947 | 2573.225 | +1 % |
| `fib` | 26 | 317 | +1112 % | 4130.289 | 4241.378 | +3 % |
| `collatz` | 26 | 317 | +1113 % | 2495.242 | 2627.914 | +5 % |
| `matmul` | 27 | 317 | +1096 % | 2918.376 | 3036.565 | +4 % |
| `json_parse` | 53 | 337 | +542 % | 1438.500 | 1589.497 | +10 % |
| `nbody` | 28 | 319 | +1037 % | 4395.166 | 4481.337 | +2 % |
| `chacha20` | 48 | 364 | +659 % | 3958.157 | 4065.739 | +3 % |
| `poly1305` | 35 | 321 | +827 % | 12479.814 | 12608.043 | +1 % |
| `blake2b` | 43 | 329 | +672 % | 4645.939 | 4764.655 | +3 % |
| `sha512` | 40 | 327 | +722 % | 5350.392 | 5472.235 | +2 % |
| `x25519` | 49 | 339 | +590 % | 35255.764 | 35327.407 | +0 % |

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
| _(floor: empty program)_ | _4.489_ | _119.410_ | _57.617_ | _62.950_ | _44.532_ | _66.003_ | _81.472_ |
| `lcg` | 4.844 | 135.991 | 59.201 | 73.248 | 44.475 | 73.382 | 87.637 |
| `packet_classifier` | 4.939 | 139.297 | 60.232 | 73.798 | 45.804 | 75.017 | 90.139 |
| `ring_write` | 14.064 | 148.145 | 70.360 | 73.349 | 44.567 | 74.932 | 88.760 |
| `histogram_bins` | 14.120 | 151.467 | 70.544 | 75.606 | 44.529 | 77.221 | 89.930 |
| `prefix_scan` | 14.225 | 152.032 | 71.811 | 77.878 | 43.121 | 76.990 | 90.863 |
| `binary_search` | 14.405 | 152.891 | 73.034 | 74.438 | 44.979 | 81.137 | 92.963 |
| `sort_window` | 14.484 | 157.828 | 79.614 | 79.746 | 45.035 | 83.266 | 98.789 |
| `bloom_filter` | 15.521 | 163.127 | 83.267 | 83.670 | 46.725 | 82.352 | 97.216 |
| `hash_join` | 18.647 | 278.265 | 83.844 | 124.333 | 44.183 | 116.314 | 128.664 |
| `sieve` | 14.204 | 155.019 | 71.696 | 85.078 | 44.642 | 90.172 | 99.044 |
| `fib` | 4.793 | 136.332 | 58.332 | 72.776 | 43.516 | 75.328 | 86.739 |
| `collatz` | 4.923 | 139.760 | 57.652 | 73.165 | 44.294 | 75.168 | 85.971 |
| `matmul` | 15.825 | 159.853 | 74.813 | 86.064 | 43.855 | 96.330 | 105.159 |
| `json_parse` | 48.451 | 772.921 | 162.114 | 130.035 | 45.630 | 181.094 | 164.000 |
| `nbody` | 16.744 | 172.398 | 84.182 | 101.508 | 45.205 | 98.796 | 110.269 |
| `chacha20` | 49.510 | 828.017 | 207.980 | 116.770 | 44.526 | 118.015 | 128.192 |
| `poly1305` | 33.086 | 371.053 | 112.919 | 118.568 | 44.359 | 126.533 | 136.751 |
| `blake2b` | 36.884 | 559.691 | 120.602 | 115.014 | 42.689 | 129.861 | 137.587 |
| `sha512` | 36.553 | 493.430 | 125.043 | 101.921 | 42.988 | 117.099 | 126.104 |
| `x25519` | 36.505 | 993.554 | 127.885 | 790.663 | 43.887 | 659.213 | 679.741 |

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
