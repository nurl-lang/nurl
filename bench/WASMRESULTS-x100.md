# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-28T03:09:05Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `8c17928f901cd70086613f6fb8de1385ff604854` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40621852847 |
| NURL | `v0.79.1-4-g8c17928f` |
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
| _(floor: empty program)_ | _1.091_ | _8.508_ | _7.8_ | _1.106_ | _4.938_ | _4.5_ | _1.217_ | _20.913_ | _17.2_ |
| `lcg` | 2801.950 | 2850.444 | 1.0 | 2766.828 | 2769.820 | 1.0 | 2805.657 | 2854.340 | 1.0 |
| `packet_classifier` | 4058.391 | 3143.257 | 0.8 | 4054.206 | 3211.069 | 0.8 | 3961.723 | 3253.510 | 0.8 |
| `ring_write` | 2839.891 | 3322.822 | 1.2 | 2808.786 | 3335.571 | 1.2 | 2816.091 | 3331.014 | 1.2 |
| `histogram_bins` | 2794.197 | 3195.799 | 1.1 | 2765.106 | 3272.831 | 1.2 | 2745.218 | 3286.374 | 1.2 |
| `prefix_scan` | 1499.330 | 434.969 | 0.3 | 1503.384 | 484.931 | 0.3 | 1511.775 | 439.164 | 0.3 |
| `binary_search` | 1404.298 | 4008.851 | 2.9 | 1354.348 | 4250.115 | 3.1 | 1574.909 | 4051.451 | 2.6 |
| `sort_window` | 1967.822 | 2394.221 | 1.2 | 2350.102 | 1878.034 | 0.8 | 1913.199 | 1870.255 | 1.0 |
| `bloom_filter` | 764.606 | 791.384 | 1.0 | 767.476 | 843.592 | 1.1 | 766.496 | 767.612 | 1.0 |
| `hash_join` | 1552.522 | 2350.352 | 1.5 | 1682.619 | 2413.177 | 1.4 | 1712.825 | 2410.413 | 1.4 |
| `sieve` | 994.175 | 1119.931 | 1.1 | 1007.142 | 1250.235 | 1.2 | 987.712 | 1301.790 | 1.3 |
| `fib` | 1752.760 | 2329.317 | 1.3 | 1831.713 | 2285.633 | 1.2 | 1837.105 | 2286.160 | 1.2 |
| `collatz` | 1156.612 | 1933.134 | 1.7 | 1195.709 | 1946.972 | 1.6 | 1181.336 | 1932.774 | 1.6 |
| `matmul` | 1953.827 | 1787.446 | 0.9 | 1956.781 | 1715.682 | 0.9 | 1946.391 | 1786.060 | 0.9 |
| `json_parse` | 360.920 | 866.848 | 2.4 | 405.833 | 342.423 | 0.8 | 530.258 | 665.228 | 1.3 |
| `nbody` | 2474.734 | 2484.723 | 1.0 | 2470.714 | 2392.928 | 1.0 | 2333.827 | 2373.249 | 1.0 |
| `chacha20` | 566.538 | 2265.332 | 4.0 | 1907.456 | 2475.134 | 1.3 | 1985.451 | 2481.974 | 1.3 |
| `poly1305` | 757.078 | 6188.310 | 8.2 | 1506.026 | 6267.449 | 4.2 | 1504.381 | 7712.327 | 5.1 |
| `blake2b` | 2556.780 | 2890.713 | 1.1 | 4282.516 | 4795.841 | 1.1 | 4771.093 | 5652.722 | 1.2 |
| `sha512` | 2959.583 | 3505.343 | 1.2 | 3271.808 | 3722.029 | 1.1 | 3148.158 | 3653.268 | 1.2 |
| `x25519` | 2444.231 | 15265.116 | 6.2 | 3336.714 | 16872.461 | 5.1 | 3164.837 | 22865.127 | 7.2 |

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
| `packet_classifier` | 0.8 | 0.8 | 0.8 | 0.8 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.2 |
| `histogram_bins` | 1.1 | 1.2 | 1.2 | 1.2 |
| `prefix_scan` | 0.3 | 0.3 | 0.3 | 0.3 |
| `binary_search` | 2.9 | 2.8 | 3.1 | 2.6 |
| `sort_window` | 1.2 | 1.1 | 0.8 | 1.0 |
| `bloom_filter` | 1.0 | 1.0 | 1.1 | 1.0 |
| `hash_join` | 1.5 | 1.5 | 1.4 | 1.4 |
| `sieve` | 1.1 | 1.1 | 1.2 | 1.3 |
| `fib` | 1.3 | 1.3 | 1.2 | 1.2 |
| `collatz` | 1.7 | 1.7 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.9 | 0.9 |
| `json_parse` | 2.4 | 2.4 | 0.8 | 1.2 |
| `nbody` | 1.0 | 1.0 | 1.0 | 1.0 |
| `chacha20` | 4.0 | 4.6 | 1.3 | 1.2 |
| `poly1305` | 8.2 | 8.2 | 4.2 | 5.1 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.2 |
| `sha512` | 1.2 | 1.2 | 1.1 | 1.2 |
| `x25519` | 6.2 | 6.2 | 5.1 | 7.2 |

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
| _(floor: empty program)_ | _8.508_ | _2.552_ | _4.938_ | _**2.206**_ | _20.913_ | _2.736_ |
| `lcg` | 2850.444 | 2828.397 | 2769.820 | **2745.104** | 2854.340 | 2820.187 |
| `packet_classifier` | 3143.257 | 2927.769 | 3211.069 | 2933.807 | 3253.510 | **2904.738** |
| `ring_write` | 3322.822 | 2858.829 | 3335.571 | 2835.378 | 3331.014 | **2824.804** |
| `histogram_bins` | 3195.799 | 2857.530 | 3272.831 | 2829.396 | 3286.374 | **2805.662** |
| `prefix_scan` | 434.969 | **399.706** | 484.931 | 427.006 | 439.164 | 400.625 |
| `binary_search` | 4008.851 | **3354.576** | 4250.115 | 3559.889 | 4051.451 | 3527.486 |
| `sort_window` | 2394.221 | 2001.951 | 1878.034 | **1796.279** | 1870.255 | 1803.907 |
| `bloom_filter` | 791.384 | **628.946** | 843.592 | 712.557 | 767.612 | 660.492 |
| `hash_join` | 2350.352 | **2303.129** | 2413.177 | 2447.100 | 2410.413 | 2417.331 |
| `sieve` | **1119.931** | 1130.022 | 1250.235 | 1250.163 | 1301.790 | 1125.061 |
| `fib` | 2329.317 | 2191.896 | 2285.633 | 1900.086 | 2286.160 | **1888.344** |
| `collatz` | 1933.134 | **1905.443** | 1946.972 | 1907.762 | 1932.774 | 1918.624 |
| `matmul` | 1787.446 | 1777.401 | **1715.682** | 1781.584 | 1786.060 | 1798.938 |
| `json_parse` | 866.848 | 829.089 | 342.423 | **318.691** | 665.228 | 612.224 |
| `nbody` | 2484.723 | 2467.088 | 2392.928 | 2478.606 | **2373.249** | 2486.249 |
| `chacha20` | 2265.332 | **2213.461** | 2475.134 | 2687.482 | 2481.974 | 2858.719 |
| `poly1305` | 6188.310 | 3234.189 | 6267.449 | **3139.432** | 7712.327 | 3174.194 |
| `blake2b` | **2890.713** | 3115.059 | 4795.841 | 4705.099 | 5652.722 | 5423.481 |
| `sha512` | **3505.343** | 3513.082 | 3722.029 | 4015.086 | 3653.268 | 3867.572 |
| `x25519` | 15265.116 | 9686.283 | 16872.461 | **7161.130** | 22865.127 | 7193.354 |

`nwasm` is faster than the reference runtime on 17 of 20 NURL modules,
15 of 20 C modules and 15 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.552_ | _0.3_ | _2.3_ | _0.4_ | _0.1_ |
| `lcg` | 2828.397 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 2927.769 | 0.9 | 0.7 | 0.9 | 0.9 |
| `ring_write` | 2858.829 | 0.9 | 1.0 | 0.9 | 0.8 |
| `histogram_bins` | 2857.530 | 0.9 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 399.706 | 0.9 | 0.3 | 0.9 | 0.9 |
| `binary_search` | 3354.576 | 0.8 | 2.4 | 0.8 | 0.9 |
| `sort_window` | 2001.951 | 0.8 | 1.0 | 1.0 | 1.0 |
| `bloom_filter` | 628.946 | 0.8 | 0.8 | 0.8 | 0.9 |
| `hash_join` | 2303.129 | 1.0 | 1.5 | 1.0 | 1.0 |
| `sieve` | 1130.022 | 1.0 | 1.1 | 1.0 | 0.9 |
| `fib` | 2191.896 | 0.9 | 1.3 | 0.8 | 0.8 |
| `collatz` | 1905.443 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 1777.401 | 1.0 | 0.9 | 1.0 | 1.0 |
| `json_parse` | 829.089 | 1.0 | 2.3 | 0.9 | 0.9 |
| `nbody` | 2467.088 | 1.0 | 1.0 | 1.0 | 1.0 |
| `chacha20` | 2213.461 | 1.0 | 3.9 | 1.1 | 1.2 |
| `poly1305` | 3234.189 | 0.5 | 4.3 | 0.5 | 0.4 |
| `blake2b` | 3115.059 | 1.1 | 1.2 | 1.0 | 1.0 |
| `sha512` | 3513.082 | 1.0 | 1.2 | 1.1 | 1.1 |
| `x25519` | 9686.283 | 0.6 | 4.0 | 0.4 | 0.3 |

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
| _(floor: empty program)_ | _4_ | _319_ | _+7928 %_ | _8.508_ | _89.855_ | _+956 %_ |
| `lcg` | 26 | 320 | +1119 % | 2850.444 | 2878.181 | +1 % |
| `packet_classifier` | 26 | 320 | +1122 % | 3143.257 | 3296.347 | +5 % |
| `ring_write` | 26 | 320 | +1119 % | 3322.822 | 3392.229 | +2 % |
| `histogram_bins` | 26 | 320 | +1117 % | 3195.799 | 3362.390 | +5 % |
| `prefix_scan` | 27 | 320 | +1103 % | 434.969 | 524.493 | +21 % |
| `binary_search` | 26 | 320 | +1115 % | 4008.851 | 4048.271 | +1 % |
| `sort_window` | 27 | 320 | +1105 % | 2394.221 | 2236.883 | −7 % |
| `bloom_filter` | 26 | 320 | +1110 % | 791.384 | 870.460 | +10 % |
| `hash_join` | 28 | 323 | +1039 % | 2350.352 | 2441.816 | +4 % |
| `sieve` | 26 | 320 | +1117 % | 1119.931 | 1192.938 | +7 % |
| `fib` | 26 | 320 | +1121 % | 2329.317 | 2386.131 | +2 % |
| `collatz` | 26 | 320 | +1123 % | 1933.134 | 2024.752 | +5 % |
| `matmul` | 27 | 320 | +1106 % | 1787.446 | 1859.016 | +4 % |
| `json_parse` | 53 | 340 | +547 % | 866.848 | 965.786 | +11 % |
| `nbody` | 28 | 321 | +1046 % | 2484.723 | 2517.580 | +1 % |
| `chacha20` | 48 | 366 | +662 % | 2265.332 | 2673.648 | +18 % |
| `poly1305` | 35 | 347 | +902 % | 6188.310 | 6286.571 | +2 % |
| `blake2b` | 43 | 332 | +678 % | 2890.713 | 2885.592 | −0 % |
| `sha512` | 40 | 330 | +728 % | 3505.343 | 3595.255 | +3 % |
| `x25519` | 47 | 339 | +614 % | 15265.116 | 15148.291 | −1 % |

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
| _(floor: empty program)_ | _3.545_ | _90.789_ | _37.251_ | _46.632_ | _30.576_ | _41.842_ | _48.376_ |
| `lcg` | 3.553 | 103.036 | 38.698 | 54.769 | 31.885 | 46.380 | 54.812 |
| `packet_classifier` | 3.639 | 102.462 | 38.495 | 54.402 | 31.677 | 47.373 | 55.619 |
| `ring_write` | 10.195 | 106.587 | 45.394 | 52.507 | 33.033 | 48.218 | 54.906 |
| `histogram_bins` | 10.328 | 113.047 | 46.725 | 56.338 | 33.558 | 49.780 | 57.892 |
| `prefix_scan` | 10.444 | 116.498 | 45.863 | 57.292 | 32.898 | 50.635 | 57.823 |
| `binary_search` | 11.181 | 117.903 | 46.538 | 55.566 | 33.362 | 52.662 | 60.526 |
| `sort_window` | 10.793 | 119.642 | 51.979 | 60.592 | 34.487 | 99.122 | 64.468 |
| `bloom_filter` | 11.069 | 114.839 | 49.277 | 59.319 | 33.076 | 53.295 | 61.520 |
| `hash_join` | 12.663 | 183.391 | 56.690 | 92.440 | 36.068 | 102.823 | 83.945 |
| `sieve` | 10.540 | 116.048 | 47.097 | 60.085 | 32.697 | 57.793 | 62.876 |
| `fib` | 3.627 | 99.768 | 37.457 | 52.985 | 31.209 | 48.431 | 55.323 |
| `collatz` | 3.659 | 96.247 | 36.053 | 50.504 | 33.020 | 47.190 | 55.412 |
| `matmul` | 11.561 | 119.583 | 50.602 | 65.236 | 35.107 | 65.973 | 72.440 |
| `json_parse` | 32.254 | 499.259 | 93.514 | 88.793 | 32.710 | 119.174 | 106.080 |
| `nbody` | 11.840 | 125.334 | 53.092 | 70.638 | 31.634 | 63.731 | 72.597 |
| `chacha20` | 34.755 | 539.927 | 108.874 | 79.534 | 33.260 | 77.465 | 85.198 |
| `poly1305` | 27.479 | 408.216 | 78.564 | 80.454 | 34.610 | 81.412 | 90.652 |
| `blake2b` | 25.081 | 363.948 | 72.259 | 81.975 | 34.105 | 86.380 | 92.169 |
| `sha512` | 23.586 | 323.379 | 77.695 | 72.880 | 33.606 | 76.539 | 81.652 |
| `x25519` | 23.841 | 607.191 | 79.203 | 474.711 | 34.435 | 407.511 | 402.720 |

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
