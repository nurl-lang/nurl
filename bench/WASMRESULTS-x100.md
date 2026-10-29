# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-29T12:28:05Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `29401773a39338856856756f52c5846acaa6b496` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40867906778 |
| NURL | `v0.80.0-54-g29401773` |
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
| _(floor: empty program)_ | _1.550_ | _11.441_ | _7.4_ | _1.599_ | _7.374_ | _4.6_ | _1.708_ | _33.830_ | _19.8_ |
| `lcg` | 3737.043 | 3764.014 | 1.0 | 3737.370 | 3765.826 | 1.0 | 3738.340 | 3769.872 | 1.0 |
| `packet_classifier` | 5473.341 | 5086.787 | 0.9 | 5452.476 | 5086.078 | 0.9 | 5449.339 | 5110.364 | 0.9 |
| `ring_write` | 4047.598 | 5009.124 | 1.2 | 4047.411 | 5009.154 | 1.2 | 4046.468 | 5016.728 | 1.2 |
| `histogram_bins` | 3736.828 | 4871.526 | 1.3 | 3948.852 | 4762.722 | 1.2 | 3736.597 | 4771.252 | 1.3 |
| `prefix_scan` | 2007.677 | 872.103 | 0.4 | 2007.822 | 889.652 | 0.4 | 2014.648 | 883.803 | 0.4 |
| `binary_search` | 3575.628 | 5728.425 | 1.6 | 3597.156 | 6003.742 | 1.7 | 4085.207 | 6017.811 | 1.5 |
| `sort_window` | 2554.629 | 4172.413 | 1.6 | 2554.709 | 2937.814 | 1.1 | 2491.914 | 3002.881 | 1.2 |
| `bloom_filter` | 1372.542 | 1530.840 | 1.1 | 1637.136 | 1589.066 | 1.0 | 1652.522 | 1489.487 | 0.9 |
| `hash_join` | 2618.904 | 4247.556 | 1.6 | 2808.666 | 4197.523 | 1.5 | 2803.969 | 4171.579 | 1.5 |
| `sieve` | 1774.061 | 2509.631 | 1.4 | 1769.133 | 2041.109 | 1.2 | 1786.704 | 2084.002 | 1.2 |
| `fib` | 2345.722 | 4112.267 | 1.8 | 2817.401 | 4099.228 | 1.5 | 2626.076 | 3760.525 | 1.4 |
| `collatz` | 1516.443 | 2498.526 | 1.6 | 1515.850 | 2496.061 | 1.6 | 1516.823 | 2499.639 | 1.6 |
| `matmul` | 3110.789 | 2928.563 | 0.9 | 3086.450 | 2507.760 | 0.8 | 3105.952 | 2337.847 | 0.8 |
| `json_parse` | 671.828 | 1462.847 | 2.2 | 686.983 | 628.874 | 0.9 | 973.614 | 1127.321 | 1.2 |
| `nbody` | 3902.180 | 4376.537 | 1.1 | 3905.390 | 3838.569 | 1.0 | 3705.574 | 3895.165 | 1.1 |
| `chacha20` | 574.563 | 3948.446 | 6.9 | 3951.767 | 4301.111 | 1.1 | 4179.813 | 4309.177 | 1.0 |
| `poly1305` | 958.675 | 11084.756 | 11.6 | 1939.568 | 11691.308 | 6.0 | 1939.156 | 13587.042 | 7.0 |
| `blake2b` | 4203.434 | 4690.809 | 1.1 | 6386.956 | 7123.444 | 1.1 | 6708.748 | 8887.466 | 1.3 |
| `sha512` | 4393.374 | 5346.521 | 1.2 | 4800.373 | 5707.716 | 1.2 | 5032.599 | 5893.855 | 1.2 |
| `x25519` | 3025.124 | 28385.017 | 9.4 | 5436.918 | 36995.229 | 6.8 | 5141.625 | 42625.250 | 8.3 |

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
| `sort_window` | 1.6 | 1.5 | 1.1 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.6 | 1.5 | 1.5 | 1.5 |
| `sieve` | 1.4 | 1.4 | 1.2 | 1.1 |
| `fib` | 1.7 | 1.7 | 1.5 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.2 | 2.2 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |
| `chacha20` | 6.9 | 6.8 | 1.1 | 1.0 |
| `poly1305` | 11.6 | 11.5 | 6.0 | 7.0 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 9.4 | 9.8 | 6.8 | 8.3 |

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
| _(floor: empty program)_ | _11.441_ | _3.678_ | _7.374_ | _**3.411**_ | _33.830_ | _5.522_ |
| `lcg` | 3764.014 | **3740.355** | 3765.826 | 3753.588 | 3769.872 | 3749.933 |
| `packet_classifier` | 5086.787 | **4673.181** | 5086.078 | 4677.489 | 5110.364 | 4678.729 |
| `ring_write` | 5009.124 | **4362.137** | 5009.154 | 4380.348 | 5016.728 | 4371.053 |
| `histogram_bins` | 4871.526 | **3887.713** | 4762.722 | 4072.453 | 4771.252 | 4290.144 |
| `prefix_scan` | 872.103 | **630.410** | 889.652 | 822.302 | 883.803 | 635.376 |
| `binary_search` | 5728.425 | **4766.761** | 6003.742 | 4796.302 | 6017.811 | 5183.651 |
| `sort_window` | 4172.413 | 4435.650 | **2937.814** | 4250.676 | 3002.881 | 4041.503 |
| `bloom_filter` | 1530.840 | **1167.169** | 1589.066 | 1236.384 | 1489.487 | 1241.841 |
| `hash_join` | 4247.556 | 3681.655 | 4197.523 | **3670.160** | 4171.579 | 3705.436 |
| `sieve` | 2509.631 | **1969.144** | 2041.109 | 1999.037 | 2084.002 | 2010.159 |
| `fib` | 4112.267 | 3523.195 | 4099.228 | 3166.823 | 3760.525 | **2833.167** |
| `collatz` | 2498.526 | **2470.964** | 2496.061 | 2477.977 | 2499.639 | 2474.984 |
| `matmul` | 2928.563 | 2618.966 | 2507.760 | **2192.919** | 2337.847 | 2250.199 |
| `json_parse` | 1462.847 | 1740.303 | **628.874** | 647.463 | 1127.321 | 1362.543 |
| `nbody` | 4376.537 | 4206.061 | **3838.569** | 3855.114 | 3895.165 | 4392.640 |
| `chacha20` | 3948.446 | **3785.073** | 4301.111 | 4942.226 | 4309.177 | 5085.685 |
| `poly1305` | 11084.756 | 7166.922 | 11691.308 | 5477.693 | 13587.042 | **5427.348** |
| `blake2b` | **4690.809** | 5898.466 | 7123.444 | 8112.716 | 8887.466 | 10088.207 |
| `sha512` | **5346.521** | 6414.886 | 5707.716 | 5956.555 | 5893.855 | 5974.892 |
| `x25519` | 28385.017 | **14316.667** | 36995.229 | 15162.641 | 42625.250 | 15456.162 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
14 of 20 C modules and 14 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.678_ | _0.3_ | _2.4_ | _0.5_ | _0.2_ |
| `lcg` | 3740.355 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4673.181 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4362.137 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3887.713 | 0.8 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 630.410 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4766.761 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4435.650 | 1.1 | 1.7 | 1.4 | 1.3 |
| `bloom_filter` | 1167.169 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 3681.655 | 0.9 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1969.144 | 0.8 | 1.1 | 1.0 | 1.0 |
| `fib` | 3523.195 | 0.9 | 1.5 | 0.8 | 0.8 |
| `collatz` | 2470.964 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2618.966 | 0.9 | 0.8 | 0.9 | 1.0 |
| `json_parse` | 1740.303 | 1.2 | 2.6 | 1.0 | 1.2 |
| `nbody` | 4206.061 | 1.0 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3785.073 | 1.0 | 6.6 | 1.1 | 1.2 |
| `poly1305` | 7166.922 | 0.6 | 7.5 | 0.5 | 0.4 |
| `blake2b` | 5898.466 | 1.3 | 1.4 | 1.1 | 1.1 |
| `sha512` | 6414.886 | 1.2 | 1.5 | 1.0 | 1.0 |
| `x25519` | 14316.667 | 0.5 | 4.7 | 0.4 | 0.4 |

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
| `json_parse` | 50 | 53 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 18 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 57 | 48 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 49 | 35 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 41 | 43 | 16 | 925 | 4435 | 2127 |
| `sha512` | 37 | 40 | 16 | 922 | 4433 | 2126 |
| `x25519` | 49 | 48 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _319_ | _+7929 %_ | _11.441_ | _151.469_ | _+1224 %_ |
| `lcg` | 26 | 320 | +1119 % | 3764.014 | 3886.882 | +3 % |
| `packet_classifier` | 26 | 320 | +1122 % | 5086.787 | 5208.874 | +2 % |
| `ring_write` | 26 | 320 | +1120 % | 5009.124 | 5134.097 | +2 % |
| `histogram_bins` | 26 | 320 | +1117 % | 4871.526 | 5420.682 | +11 % |
| `prefix_scan` | 27 | 320 | +1104 % | 872.103 | 1003.965 | +15 % |
| `binary_search` | 26 | 320 | +1115 % | 5728.425 | 5795.710 | +1 % |
| `sort_window` | 27 | 320 | +1105 % | 4172.413 | 4000.800 | −4 % |
| `bloom_filter` | 26 | 320 | +1110 % | 1530.840 | 1653.830 | +8 % |
| `hash_join` | 28 | 323 | +1039 % | 4247.556 | 4132.568 | −3 % |
| `sieve` | 26 | 320 | +1117 % | 2509.631 | 2641.945 | +5 % |
| `fib` | 26 | 320 | +1121 % | 4112.267 | 4228.809 | +3 % |
| `collatz` | 26 | 320 | +1123 % | 2498.526 | 2618.803 | +5 % |
| `matmul` | 27 | 320 | +1106 % | 2928.563 | 3037.702 | +4 % |
| `json_parse` | 53 | 340 | +545 % | 1462.847 | 1626.515 | +11 % |
| `nbody` | 28 | 321 | +1046 % | 4376.537 | 4486.508 | +3 % |
| `chacha20` | 48 | 366 | +662 % | 3948.446 | 4067.324 | +3 % |
| `poly1305` | 35 | 347 | +902 % | 11084.756 | 11198.403 | +1 % |
| `blake2b` | 43 | 332 | +679 % | 4690.809 | 4817.792 | +3 % |
| `sha512` | 40 | 330 | +728 % | 5346.521 | 5476.371 | +2 % |
| `x25519` | 48 | 351 | +633 % | 28385.017 | 29768.151 | +5 % |

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
| _(floor: empty program)_ | _4.596_ | _119.631_ | _53.107_ | _61.503_ | _46.206_ | _65.229_ | _77.330_ |
| `lcg` | 4.899 | 139.933 | 54.778 | 76.185 | 42.779 | 72.807 | 85.063 |
| `packet_classifier` | 5.130 | 147.627 | 55.967 | 75.846 | 44.508 | 75.784 | 88.638 |
| `ring_write` | 15.600 | 156.048 | 69.315 | 77.367 | 45.647 | 76.074 | 88.575 |
| `histogram_bins` | 16.587 | 162.302 | 71.193 | 78.147 | 45.527 | 79.190 | 92.931 |
| `prefix_scan` | 16.163 | 159.158 | 68.029 | 76.782 | 42.535 | 77.772 | 88.964 |
| `binary_search` | 16.440 | 158.926 | 68.987 | 77.471 | 43.713 | 80.374 | 90.714 |
| `sort_window` | 15.982 | 162.252 | 76.898 | 80.604 | 44.168 | 84.555 | 96.074 |
| `bloom_filter` | 16.477 | 163.784 | 71.589 | 82.309 | 44.157 | 81.219 | 93.737 |
| `hash_join` | 19.850 | 279.881 | 83.059 | 123.709 | 42.704 | 114.221 | 129.101 |
| `sieve` | 15.850 | 156.621 | 72.022 | 83.192 | 42.722 | 89.975 | 98.560 |
| `fib` | 5.141 | 141.503 | 54.002 | 71.686 | 45.272 | 74.494 | 87.868 |
| `collatz` | 5.300 | 147.883 | 55.303 | 75.295 | 44.302 | 74.859 | 90.688 |
| `matmul` | 17.569 | 165.276 | 72.753 | 86.338 | 42.589 | 97.777 | 106.653 |
| `json_parse` | 51.243 | 735.866 | 159.405 | 129.541 | 45.529 | 179.386 | 165.353 |
| `nbody` | 18.980 | 181.327 | 83.372 | 103.405 | 44.144 | 99.475 | 108.347 |
| `chacha20` | 58.785 | 850.583 | 188.634 | 116.345 | 43.137 | 118.807 | 130.494 |
| `poly1305` | 44.958 | 628.420 | 129.262 | 120.432 | 43.388 | 129.038 | 138.140 |
| `blake2b` | 39.901 | 570.467 | 115.279 | 118.371 | 43.065 | 132.475 | 138.647 |
| `sha512` | 40.109 | 507.807 | 129.602 | 109.777 | 44.633 | 119.566 | 130.454 |
| `x25519` | 54.825 | 1310.642 | 167.192 | 806.786 | 45.142 | 667.365 | 691.688 |

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
