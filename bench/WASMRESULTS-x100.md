# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-07T21:40:15Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `7f9c039b8eaaff1d5acc9536be869b13d9d084cc` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37687919677 |
| NURL | `v0.70.0-39-g7f9c039b` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.2), built from this repo |
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
| _(floor: empty program)_ | _1.516_ | _12.511_ | _8.3_ | _1.585_ | _7.430_ | _4.7_ | _1.738_ | _36.036_ | _20.7_ |
| `lcg` | 3736.880 | 3763.569 | 1.0 | 3736.421 | 3763.698 | 1.0 | 3736.917 | 3769.446 | 1.0 |
| `packet_classifier` | 5446.446 | 5087.062 | 0.9 | 5446.205 | 5085.736 | 0.9 | 5447.148 | 5094.250 | 0.9 |
| `ring_write` | 4050.329 | 5009.623 | 1.2 | 4048.219 | 5007.607 | 1.2 | 4048.182 | 5013.414 | 1.2 |
| `histogram_bins` | 3779.079 | 5302.726 | 1.4 | 3944.089 | 4764.626 | 1.2 | 3736.008 | 4771.618 | 1.3 |
| `prefix_scan` | 2009.327 | 875.777 | 0.4 | 2008.423 | 888.897 | 0.4 | 2013.962 | 883.426 | 0.4 |
| `binary_search` | 3579.361 | 5735.901 | 1.6 | 3577.218 | 6017.311 | 1.7 | 4083.520 | 6014.131 | 1.5 |
| `sort_window` | 2557.604 | 3861.159 | 1.5 | 2554.008 | 2931.445 | 1.1 | 2492.522 | 3005.073 | 1.2 |
| `bloom_filter` | 1373.432 | 1506.310 | 1.1 | 1635.760 | 1586.604 | 1.0 | 1651.260 | 1495.338 | 0.9 |
| `hash_join` | 2617.343 | 3572.067 | 1.4 | 2806.523 | 4190.446 | 1.5 | 2806.538 | 4171.489 | 1.5 |
| `sieve` | 1542.363 | 2130.352 | 1.4 | 1544.886 | 2139.490 | 1.4 | 1537.713 | 2175.996 | 1.4 |
| `fib` | 2346.785 | 3899.039 | 1.7 | 2818.656 | 4046.294 | 1.4 | 2626.666 | 3771.889 | 1.4 |
| `collatz` | 1515.430 | 2496.612 | 1.6 | 1515.140 | 2494.693 | 1.6 | 1516.445 | 2498.275 | 1.6 |
| `matmul` | 3113.838 | 2928.775 | 0.9 | 3119.654 | 2513.954 | 0.8 | 3101.261 | 2346.142 | 0.8 |
| `json_parse` | 709.279 | 1521.928 | 2.1 | 688.094 | 607.873 | 0.9 | 974.339 | 1134.981 | 1.2 |
| `nbody` | 3902.326 | 4362.114 | 1.1 | 3899.370 | 3833.835 | 1.0 | 3703.302 | 3899.014 | 1.1 |

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
| `sieve` | 1.4 | 1.4 | 1.4 | 1.4 |
| `fib` | 1.7 | 1.7 | 1.4 | 1.4 |
| `collatz` | 1.6 | 1.6 | 1.6 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 2.1 | 2.3 | 0.9 | 1.1 |
| `nbody` | 1.1 | 1.1 | 1.0 | 1.0 |

## 3. The pure-NURL runtime (`packages/nwasm`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with a template
JIT on top (on by default; `NURL_NWASM_JIT=0` keeps the pure interpreter,
and metered or shared-memory runs fall back to it on their own).
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
| _(floor: empty program)_ | _12.511_ | _**3.238**_ | _7.430_ | _3.399_ | _36.036_ | _4.416_ |
| `lcg` | 3763.569 | **3739.062** | 3763.698 | 3744.616 | 3769.446 | 3743.073 |
| `packet_classifier` | 5087.062 | **4675.433** | 5085.736 | 4677.491 | 5094.250 | 4677.027 |
| `ring_write` | 5009.623 | **4361.261** | 5007.607 | 4366.867 | 5013.414 | 4367.485 |
| `histogram_bins` | 5302.726 | **3887.599** | 4764.626 | 4054.400 | 4771.618 | 4285.320 |
| `prefix_scan` | 875.777 | **632.261** | 888.897 | 820.049 | 883.426 | 635.396 |
| `binary_search` | 5735.901 | **4698.489** | 6017.311 | 4797.301 | 6014.131 | 5180.336 |
| `sort_window` | 3861.159 | 4407.367 | **2931.445** | 4264.467 | 3005.073 | 4048.184 |
| `bloom_filter` | 1506.310 | **1169.646** | 1586.604 | 1311.915 | 1495.338 | 1317.213 |
| `hash_join` | **3572.067** | 3650.741 | 4190.446 | 3721.848 | 4171.489 | 3773.067 |
| `sieve` | 2130.352 | **1928.691** | 2139.490 | 2020.141 | 2175.996 | 2002.297 |
| `fib` | 3899.039 | 3509.072 | 4046.294 | 3167.842 | 3771.889 | **2829.505** |
| `collatz` | 2496.612 | **2469.543** | 2494.693 | 2474.820 | 2498.275 | 2473.670 |
| `matmul` | 2928.775 | 2633.148 | 2513.954 | 2479.184 | 2346.142 | **2254.603** |
| `json_parse` | 1521.928 | 1881.506 | **607.873** | 662.486 | 1134.981 | 1414.092 |
| `nbody` | 4362.114 | 4315.121 | **3833.835** | 3867.225 | 3899.014 | 4394.144 |

`nwasm` is faster than the reference runtime on 12 of 15 NURL modules,
12 of 15 C modules and 12 of 15 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.238_ | _0.3_ | _2.1_ | _0.5_ | _0.1_ |
| `lcg` | 3739.062 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 4675.433 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 4361.261 | 0.9 | 1.1 | 0.9 | 0.9 |
| `histogram_bins` | 3887.599 | 0.7 | 1.0 | 0.9 | 0.9 |
| `prefix_scan` | 632.261 | 0.7 | 0.3 | 0.9 | 0.7 |
| `binary_search` | 4698.489 | 0.8 | 1.3 | 0.8 | 0.9 |
| `sort_window` | 4407.367 | 1.1 | 1.7 | 1.5 | 1.3 |
| `bloom_filter` | 1169.646 | 0.8 | 0.9 | 0.8 | 0.9 |
| `hash_join` | 3650.741 | 1.0 | 1.4 | 0.9 | 0.9 |
| `sieve` | 1928.691 | 0.9 | 1.3 | 0.9 | 0.9 |
| `fib` | 3509.072 | 0.9 | 1.5 | 0.8 | 0.8 |
| `collatz` | 2469.543 | 1.0 | 1.6 | 1.0 | 1.0 |
| `matmul` | 2633.148 | 0.9 | 0.8 | 1.0 | 1.0 |
| `json_parse` | 1881.506 | 1.2 | 2.7 | 1.1 | 1.2 |
| `nbody` | 4315.121 | 1.0 | 1.1 | 1.0 | 1.1 |

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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _12.511_ | _152.572_ | _+1120 %_ |
| `lcg` | 26 | 311 | +1087 % | 3763.569 | 3888.875 | +3 % |
| `packet_classifier` | 26 | 311 | +1090 % | 5087.062 | 5209.124 | +2 % |
| `ring_write` | 26 | 311 | +1087 % | 5009.623 | 5127.897 | +2 % |
| `histogram_bins` | 26 | 311 | +1084 % | 5302.726 | 5042.065 | −5 % |
| `prefix_scan` | 27 | 311 | +1071 % | 875.777 | 998.565 | +14 % |
| `binary_search` | 26 | 311 | +1082 % | 5735.901 | 5886.114 | +3 % |
| `sort_window` | 27 | 312 | +1073 % | 3861.159 | 4035.001 | +5 % |
| `bloom_filter` | 26 | 312 | +1078 % | 1506.310 | 1635.416 | +9 % |
| `hash_join` | 28 | 314 | +1009 % | 3572.067 | 3733.230 | +5 % |
| `sieve` | 26 | 311 | +1085 % | 2130.352 | 2244.251 | +5 % |
| `fib` | 26 | 311 | +1089 % | 3899.039 | 4232.971 | +9 % |
| `collatz` | 26 | 311 | +1091 % | 2496.612 | 2616.683 | +5 % |
| `matmul` | 27 | 311 | +1074 % | 2928.775 | 3052.211 | +4 % |
| `json_parse` | 50 | 331 | +561 % | 1521.928 | 1750.622 | +15 % |
| `nbody` | 28 | 313 | +1016 % | 4362.114 | 4505.207 | +3 % |

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
| _(floor: empty program)_ | _3.576_ | _108.043_ | _55.105_ | _62.264_ | _44.032_ | _66.723_ | _80.478_ |
| `lcg` | 3.793 | 125.986 | 54.254 | 72.245 | 43.092 | 73.242 | 88.876 |
| `packet_classifier` | 3.987 | 127.111 | 54.955 | 71.709 | 46.418 | 72.769 | 85.698 |
| `ring_write` | 4.223 | 132.587 | 56.211 | 73.223 | 44.673 | 76.956 | 89.443 |
| `histogram_bins` | 4.251 | 133.455 | 56.109 | 75.320 | 43.982 | 78.991 | 89.168 |
| `prefix_scan` | 4.383 | 133.608 | 55.765 | 77.859 | 44.157 | 77.945 | 90.866 |
| `binary_search` | 4.524 | 131.028 | 57.991 | 71.972 | 44.356 | 81.693 | 92.564 |
| `sort_window` | 4.722 | 136.805 | 56.573 | 79.879 | 44.615 | 87.003 | 96.584 |
| `bloom_filter` | 5.408 | 141.275 | 58.783 | 83.078 | 44.191 | 80.848 | 94.222 |
| `hash_join` | 9.418 | 258.862 | 70.961 | 126.559 | 44.189 | 117.580 | 128.979 |
| `sieve` | 4.552 | 136.309 | 56.544 | 85.774 | 44.141 | 87.811 | 98.802 |
| `fib` | 4.107 | 127.703 | 54.792 | 73.042 | 43.845 | 74.338 | 87.278 |
| `collatz` | 4.208 | 128.108 | 56.262 | 72.676 | 44.964 | 73.117 | 88.456 |
| `matmul` | 5.944 | 142.002 | 58.362 | 85.893 | 44.036 | 97.259 | 105.767 |
| `json_parse` | 48.031 | 683.725 | 155.364 | 129.376 | 44.310 | 176.682 | 159.616 |
| `nbody` | 7.126 | 151.713 | 68.549 | 102.248 | 44.006 | 96.530 | 107.633 |

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
