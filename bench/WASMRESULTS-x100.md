# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-10T09:43:19Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `ff246f32bbb1723087c88f76ca199b9edb050911` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38039908183 |
| NURL | `v0.71.0-25-gff246f32` |
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
| _(floor: empty program)_ | _1.575_ | _11.577_ | _7.4_ | _1.611_ | _6.673_ | _4.1_ | _1.766_ | _34.724_ | _19.7_ |
| `lcg` | 4217.035 | 4244.750 | 1.0 | 4219.986 | 4246.836 | 1.0 | 4217.841 | 4252.673 | 1.0 |
| `packet_classifier` | 6150.045 | 5738.221 | 0.9 | 6148.791 | 5737.461 | 0.9 | 6148.801 | 5741.634 | 0.9 |
| `ring_write` | 4568.980 | 5650.100 | 1.2 | 4568.556 | 5650.006 | 1.2 | 4568.782 | 5653.933 | 1.2 |
| `histogram_bins` | 4268.663 | 5549.279 | 1.3 | 4267.016 | 5469.425 | 1.3 | 4267.730 | 5264.695 | 1.2 |
| `prefix_scan` | 2268.958 | 982.313 | 0.4 | 2268.442 | 954.336 | 0.4 | 2273.336 | 984.833 | 0.4 |
| `binary_search` | 3382.230 | 6219.146 | 1.8 | 3371.213 | 6483.506 | 1.9 | 4400.293 | 6370.509 | 1.4 |
| `sort_window` | 2883.365 | 4191.387 | 1.5 | 2885.211 | 3466.078 | 1.2 | 2815.712 | 3372.771 | 1.2 |
| `bloom_filter` | 1550.224 | 1705.387 | 1.1 | 1844.389 | 1789.440 | 1.0 | 1863.691 | 1681.236 | 0.9 |
| `hash_join` | 2695.586 | 3743.918 | 1.4 | 2857.931 | 4191.005 | 1.5 | 2883.365 | 4263.092 | 1.5 |
| `sieve` | 1750.167 | 2575.820 | 1.5 | 1750.775 | 2035.783 | 1.2 | 1750.163 | 2022.469 | 1.2 |
| `fib` | 2605.735 | 4111.604 | 1.6 | 3135.227 | 4202.761 | 1.3 | 2727.954 | 4141.701 | 1.5 |
| `collatz` | 1688.159 | 2775.774 | 1.6 | 1684.680 | 2774.436 | 1.6 | 1691.495 | 2773.320 | 1.6 |
| `matmul` | 4372.955 | 3798.726 | 0.9 | 4362.678 | 3080.481 | 0.7 | 4346.845 | 2828.265 | 0.7 |
| `json_parse` | 641.131 | 1438.362 | 2.2 | 680.855 | 616.862 | 0.9 | 955.537 | 1127.165 | 1.2 |
| `nbody` | 4417.832 | 4368.241 | 1.0 | 4418.549 | 4309.098 | 1.0 | 4187.443 | 4271.829 | 1.0 |
| `chacha20` | 731.086 | 4107.840 | 5.6 | 4406.465 | 4636.894 | 1.1 | 4367.504 | 4602.404 | 1.1 |
| `poly1305` | 2459.265 | 11290.366 | 4.6 | 2185.772 | 11032.424 | 5.0 | 2189.931 | 14005.121 | 6.4 |
| `blake2b` | 4683.345 | 5178.285 | 1.1 | 7169.209 | 8352.598 | 1.2 | 7589.607 | 9717.777 | 1.3 |
| `sha512` | 4755.249 | 5865.540 | 1.2 | 5134.678 | 6063.738 | 1.2 | 5192.226 | 6155.265 | 1.2 |
| `x25519` | 5823.588 | 32389.988 | 5.6 | 6066.906 | 34053.001 | 5.6 | 5700.227 | 44652.462 | 7.8 |

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
| `histogram_bins` | 1.3 | 1.4 | 1.3 | 1.2 |
| `prefix_scan` | 0.4 | 0.4 | 0.4 | 0.4 |
| `binary_search` | 1.8 | 1.8 | 1.9 | 1.4 |
| `sort_window` | 1.5 | 1.4 | 1.2 | 1.2 |
| `bloom_filter` | 1.1 | 1.1 | 1.0 | 0.9 |
| `hash_join` | 1.4 | 1.4 | 1.5 | 1.5 |
| `sieve` | 1.5 | 1.5 | 1.2 | 1.1 |
| `fib` | 1.6 | 1.7 | 1.3 | 1.5 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.7 | 0.6 |
| `json_parse` | 2.2 | 2.2 | 0.9 | 1.1 |
| `nbody` | 1.0 | 1.0 | 1.0 | 1.0 |
| `chacha20` | 5.6 | 5.6 | 1.1 | 1.0 |
| `poly1305` | 4.6 | 4.6 | 5.0 | 6.4 |
| `blake2b` | 1.1 | 1.1 | 1.2 | 1.3 |
| `sha512` | 1.2 | 1.2 | 1.2 | 1.2 |
| `x25519` | 5.6 | 5.5 | 5.6 | 7.8 |

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
| _(floor: empty program)_ | _11.577_ | _3.915_ | _6.673_ | _**2.852**_ | _34.724_ | _3.482_ |
| `lcg` | 4244.750 | **4222.062** | 4246.836 | 4225.974 | 4252.673 | 4225.568 |
| `packet_classifier` | 5738.221 | **5275.376** | 5737.461 | 5278.186 | 5741.634 | 5281.193 |
| `ring_write` | 5650.100 | **4922.325** | 5650.006 | 4927.108 | 5653.933 | 4929.496 |
| `histogram_bins` | 5549.279 | **4386.152** | 5469.425 | 4492.888 | 5264.695 | 4391.102 |
| `prefix_scan` | 982.313 | **709.654** | 954.336 | 937.967 | 984.833 | 712.666 |
| `binary_search` | 6219.146 | **5035.503** | 6483.506 | 5152.124 | 6370.509 | 5596.917 |
| `sort_window` | 4191.387 | 4379.226 | 3466.078 | 3975.225 | **3372.771** | 3823.012 |
| `bloom_filter` | 1705.387 | 1409.584 | 1789.440 | **1392.279** | 1681.236 | 1401.592 |
| `hash_join` | 3743.918 | **3734.355** | 4191.005 | 3811.758 | 4263.092 | 3817.663 |
| `sieve` | 2575.820 | **1919.675** | 2035.783 | 1984.837 | 2022.469 | 2001.239 |
| `fib` | 4111.604 | 3786.890 | 4202.761 | 3389.841 | 4141.701 | **2950.695** |
| `collatz` | 2775.774 | **2741.978** | 2774.436 | 2746.917 | 2773.320 | 2746.787 |
| `matmul` | 3798.726 | 3313.113 | 3080.481 | 2508.173 | 2828.265 | **2407.193** |
| `json_parse` | 1438.362 | 1499.079 | 616.862 | **564.537** | 1127.165 | 1126.807 |
| `nbody` | 4368.241 | 5035.732 | 4309.098 | 4316.151 | **4271.829** | 4594.758 |
| `chacha20` | 4107.840 | **3974.231** | 4636.894 | 4912.503 | 4602.404 | 5019.643 |
| `poly1305` | 11290.366 | 7522.841 | 11032.424 | **5794.813** | 14005.121 | 6007.778 |
| `blake2b` | **5178.285** | 5868.758 | 8352.598 | 8711.163 | 9717.777 | 10538.589 |
| `sha512` | 5865.540 | **5664.009** | 6063.738 | 6439.310 | 6155.265 | 6552.868 |
| `x25519` | 32389.988 | 15698.696 | 34053.001 | **15455.075** | 44652.462 | 15491.371 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
15 of 20 C modules and 15 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.915_ | _0.3_ | _2.5_ | _0.4_ | _0.1_ |
| `lcg` | 4222.062 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 5275.376 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4922.325 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 4386.152 | 0.8 | 1.0 | 0.8 | 0.8 |
| `prefix_scan` | 709.654 | 0.7 | 0.3 | 1.0 | 0.7 |
| `binary_search` | 5035.503 | 0.8 | 1.5 | 0.8 | 0.9 |
| `sort_window` | 4379.226 | 1.0 | 1.5 | 1.1 | 1.1 |
| `bloom_filter` | 1409.584 | 0.8 | 0.9 | 0.8 | 0.8 |
| `hash_join` | 3734.355 | 1.0 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1919.675 | 0.7 | 1.1 | 1.0 | 1.0 |
| `fib` | 3786.890 | 0.9 | 1.5 | 0.8 | 0.7 |
| `collatz` | 2741.978 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 3313.113 | 0.9 | 0.8 | 0.8 | 0.9 |
| `json_parse` | 1499.079 | 1.0 | 2.3 | 0.9 | 1.0 |
| `nbody` | 5035.732 | 1.2 | 1.1 | 1.0 | 1.1 |
| `chacha20` | 3974.231 | 1.0 | 5.4 | 1.1 | 1.1 |
| `poly1305` | 7522.841 | 0.7 | 3.1 | 0.5 | 0.4 |
| `blake2b` | 5868.758 | 1.1 | 1.3 | 1.0 | 1.1 |
| `sha512` | 5664.009 | 1.0 | 1.2 | 1.1 | 1.1 |
| `x25519` | 15698.696 | 0.5 | 2.7 | 0.5 | 0.3 |

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
| _(floor: empty program)_ | _4_ | _312_ | _+7737 %_ | _11.577_ | _146.670_ | _+1167 %_ |
| `lcg` | 26 | 312 | +1090 % | 4244.750 | 4364.405 | +3 % |
| `packet_classifier` | 26 | 312 | +1093 % | 5738.221 | 5848.479 | +2 % |
| `ring_write` | 26 | 312 | +1090 % | 5650.100 | 5766.814 | +2 % |
| `histogram_bins` | 26 | 312 | +1088 % | 5549.279 | 6105.387 | +10 % |
| `prefix_scan` | 27 | 312 | +1074 % | 982.313 | 1099.789 | +12 % |
| `binary_search` | 26 | 312 | +1085 % | 6219.146 | 6338.619 | +2 % |
| `sort_window` | 27 | 313 | +1076 % | 4191.387 | 4117.833 | −2 % |
| `bloom_filter` | 26 | 312 | +1081 % | 1705.387 | 1808.157 | +6 % |
| `hash_join` | 28 | 315 | +1012 % | 3743.918 | 3819.521 | +2 % |
| `sieve` | 26 | 312 | +1088 % | 2575.820 | 2701.051 | +5 % |
| `fib` | 26 | 312 | +1092 % | 4111.604 | 4453.882 | +8 % |
| `collatz` | 26 | 312 | +1094 % | 2775.774 | 2887.333 | +4 % |
| `matmul` | 27 | 312 | +1077 % | 3798.726 | 3923.221 | +3 % |
| `json_parse` | 52 | 332 | +534 % | 1438.362 | 1538.208 | +7 % |
| `nbody` | 28 | 314 | +1019 % | 4368.241 | 4486.014 | +3 % |
| `chacha20` | 48 | 359 | +646 % | 4107.840 | 4239.820 | +3 % |
| `poly1305` | 35 | 316 | +813 % | 11290.366 | 11391.182 | +1 % |
| `blake2b` | 42 | 325 | +679 % | 5178.285 | 5289.300 | +2 % |
| `sha512` | 40 | 322 | +709 % | 5865.540 | 5968.044 | +2 % |
| `x25519` | 43 | 326 | +656 % | 32389.988 | 32457.132 | +0 % |

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
| _(floor: empty program)_ | _3.996_ | _107.606_ | _55.316_ | _65.177_ | _44.814_ | _64.621_ | _84.954_ |
| `lcg` | 4.236 | 127.237 | 55.343 | 72.003 | 44.755 | 71.944 | 86.023 |
| `packet_classifier` | 4.358 | 126.444 | 58.899 | 73.769 | 44.257 | 73.027 | 85.335 |
| `ring_write` | 4.568 | 127.831 | 58.359 | 73.481 | 44.802 | 74.994 | 87.275 |
| `histogram_bins` | 4.741 | 132.874 | 56.530 | 77.317 | 44.992 | 77.309 | 89.595 |
| `prefix_scan` | 4.852 | 132.716 | 56.065 | 77.087 | 44.338 | 76.782 | 89.464 |
| `binary_search` | 4.942 | 130.959 | 56.859 | 74.432 | 46.517 | 80.296 | 91.264 |
| `sort_window` | 5.218 | 137.929 | 58.383 | 80.043 | 45.082 | 83.183 | 94.912 |
| `bloom_filter` | 5.683 | 136.852 | 59.035 | 81.090 | 44.896 | 79.170 | 92.092 |
| `hash_join` | 9.834 | 248.621 | 70.915 | 121.714 | 46.280 | 114.382 | 128.585 |
| `sieve` | 4.986 | 134.109 | 57.296 | 82.912 | 44.546 | 87.103 | 96.260 |
| `fib` | 4.502 | 127.342 | 54.844 | 73.291 | 44.712 | 74.180 | 86.366 |
| `collatz` | 4.576 | 129.380 | 55.503 | 72.173 | 44.648 | 73.579 | 86.825 |
| `matmul` | 6.570 | 138.814 | 59.603 | 85.527 | 44.581 | 95.769 | 104.182 |
| `json_parse` | 51.088 | 705.067 | 163.144 | 123.354 | 45.077 | 175.819 | 156.601 |
| `nbody` | 7.451 | 149.756 | 68.525 | 100.012 | 45.084 | 96.684 | 108.435 |
| `chacha20` | 53.326 | 696.544 | 185.741 | 112.411 | 44.399 | 114.968 | 125.022 |
| `poly1305` | 35.330 | 341.630 | 123.249 | 117.123 | 45.040 | 125.090 | 133.300 |
| `blake2b` | 37.242 | 489.895 | 114.852 | 116.091 | 45.606 | 130.149 | 136.217 |
| `sha512` | 38.072 | 460.499 | 125.792 | 101.102 | 44.082 | 115.139 | 123.906 |
| `x25519` | 45.744 | 505.820 | 147.676 | 760.650 | 45.603 | 642.590 | 652.982 |

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
