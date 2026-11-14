# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-14T11:36:02Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-x300.json`](results/wasm-x300.json).

**Workload ×300.** Every benchmark below does 300 times its published
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
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16365628 KiB |
| Commit | `ee7cbfc554137e06fcf787a15d2050ac69d0a165` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43580288536 |
| NURL | `v0.91.1-120-gee7cbfc5` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.9), built from this repo |
| C → wasm | `zig 0.17.1 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 3.1.4 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Workload scale | ×300 — every benchmark's work multiplied by 300 before compilation |
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
| _(floor: empty program)_ | _2.416_ | _11.056_ | _4.6_ | _2.358_ | _6.150_ | _2.6_ | _2.454_ | _30.339_ | _12.4_ |
| `lcg` | 10164.135 | 10222.788 | 1.0 | 10131.565 | 10178.877 | 1.0 | 10168.762 | 10157.867 | 1.0 |
| `packet_classifier` | 16496.710 | 12841.368 | 0.8 | 18039.489 | 12760.986 | 0.7 | 17375.289 | 13495.942 | 0.8 |
| `ring_write` | 11303.486 | 13667.862 | 1.2 | 11286.417 | 13637.989 | 1.2 | 11380.438 | 13618.409 | 1.2 |
| `histogram_bins` | 10464.146 | 12503.448 | 1.2 | 10416.255 | 12379.227 | 1.2 | 10430.826 | 12548.844 | 1.2 |
| `prefix_scan` | 5495.579 | 1891.700 | 0.3 | 5418.585 | 1941.273 | 0.4 | 5507.146 | 1906.771 | 0.3 |
| `binary_search` | 6760.336 | 14093.637 | 2.1 | 6652.263 | 13440.243 | 2.0 | 11459.584 | 14975.113 | 1.3 |
| `sort_window` | 10363.095 | 11663.586 | 1.1 | 19036.451 | 8585.694 | 0.5 | 10183.879 | 8563.014 | 0.8 |
| `bloom_filter` | 3371.584 | 3445.497 | 1.0 | 3378.654 | 3057.413 | 0.9 | 3385.994 | 3120.468 | 0.9 |
| `hash_join` | 5815.386 | 10638.080 | 1.8 | 6936.855 | 8572.478 | 1.2 | 6527.888 | 10894.743 | 1.7 |
| `sieve` | 9249.495 | 9819.802 | 1.1 | 9335.212 | 11253.808 | 1.2 | 9177.663 | 10591.860 | 1.2 |
| `fib` | 7041.160 | 10275.583 | 1.5 | 6041.715 | 10326.369 | 1.7 | 7032.715 | 9442.950 | 1.3 |
| `collatz` | 5833.652 | 7354.935 | 1.3 | 5895.376 | 7359.157 | 1.2 | 5845.607 | 7329.094 | 1.3 |
| `matmul` | 4842.466 | 4361.964 | 0.9 | 4971.480 | 4210.166 | 0.8 | 4842.702 | 4416.611 | 0.9 |
| `json_parse` | 984.032 | 2447.148 | 2.5 | 1989.087 | 1497.688 | 0.8 | 2824.970 | 2246.929 | 0.8 |
| `nbody` | 8199.371 | 8578.349 | 1.0 | 8549.942 | 7901.185 | 0.9 | 7458.533 | 8079.251 | 1.1 |
| `safe_record_array` | 17658.706 | 23289.686 | 1.3 | 15530.671 | 18962.778 | 1.2 | 16908.003 | 19308.563 | 1.1 |
| `payload_state_machine` | 22761.240 | 46860.726 | 2.1 | 21233.792 | 32782.025 | 1.5 | 21034.461 | 31208.976 | 1.5 |
| `captured_closure_queue` | 27961.166 | 47890.637 | 1.7 | 23575.314 | 41368.925 | 1.8 | 29053.891 | 44448.917 | 1.5 |
| `dynamic_method_mix` | 31058.583 | 50379.230 | 1.6 | 30756.872 | 47390.923 | 1.5 | 30510.968 | 48480.262 | 1.6 |
| `csv_table_pipeline` | 16895.228 | 36705.730 | 2.2 | 22020.578 | 28820.162 | 1.3 | 17300.172 | 27708.966 | 1.6 |
| `chacha20` | 849.647 | 8138.760 | 9.6 | 8497.081 | 10102.553 | 1.2 | 8666.383 | 10098.250 | 1.2 |
| `poly1305` | 2270.433 | 21002.388 | 9.3 | 5658.591 | 20665.990 | 3.7 | 5602.830 | 25107.036 | 4.5 |
| `blake2b` | 10377.417 | 10927.153 | 1.1 | 12649.543 | 14082.526 | 1.1 | 13365.454 | 20823.724 | 1.6 |
| `sha512` | 10553.953 | 12905.083 | 1.2 | 10966.142 | 14296.018 | 1.3 | 11426.975 | 13284.315 | 1.2 |
| `x25519` | 7134.115 | 56557.782 | 7.9 | 11759.282 | 65252.757 | 5.5 | 11166.735 | 80707.358 | 7.2 |

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
| `packet_classifier` | 0.8 | 0.8 | 0.7 | 0.8 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.2 |
| `histogram_bins` | 1.2 | 1.2 | 1.2 | 1.2 |
| `prefix_scan` | 0.3 | 0.3 | 0.4 | 0.3 |
| `binary_search` | 2.1 | 2.1 | 2.0 | 1.3 |
| `sort_window` | 1.1 | 1.1 | 0.5 | 0.8 |
| `bloom_filter` | 1.0 | 1.0 | 0.9 | 0.9 |
| `hash_join` | 1.8 | 1.8 | 1.2 | 1.7 |
| `sieve` | 1.1 | 1.2 | 1.2 | 1.2 |
| `fib` | 1.5 | 1.5 | 1.7 | 1.3 |
| `collatz` | 1.3 | 1.2 | 1.2 | 1.2 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.9 |
| `json_parse` | 2.5 | 2.5 | 0.8 | 0.8 |
| `nbody` | 1.0 | 1.0 | 0.9 | 1.1 |
| `safe_record_array` | 1.3 | 1.3 | 1.2 | 1.1 |
| `payload_state_machine` | 2.1 | 2.0 | 1.5 | 1.5 |
| `captured_closure_queue` | 1.7 | 1.7 | 1.8 | 1.5 |
| `dynamic_method_mix` | 1.6 | 1.6 | 1.5 | 1.6 |
| `csv_table_pipeline` | 2.2 | 2.1 | 1.3 | 1.6 |
| `chacha20` | 9.6 | 9.7 | 1.2 | 1.2 |
| `poly1305` | 9.3 | 9.3 | 3.7 | 4.5 |
| `blake2b` | 1.1 | 1.1 | 1.1 | 1.6 |
| `sha512` | 1.2 | 1.3 | 1.3 | 1.2 |
| `x25519` | 7.9 | 7.9 | 5.5 | 7.2 |

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
| _(floor: empty program)_ | _11.056_ | _4.212_ | _6.150_ | _**3.387**_ | _30.339_ | _4.482_ |
| `lcg` | 10222.788 | 10136.533 | 10178.877 | **10121.570** | 10157.867 | 10148.631 |
| `packet_classifier` | 12841.368 | 12777.324 | **12760.986** | 12830.523 | 13495.942 | 12823.881 |
| `ring_write` | 13667.862 | 11576.141 | 13637.989 | **11488.428** | 13618.409 | 11550.844 |
| `histogram_bins` | 12503.448 | **10530.720** | 12379.227 | 10720.249 | 12548.844 | 10551.967 |
| `prefix_scan` | 1891.700 | **1712.699** | 1941.273 | 1978.933 | 1906.771 | 1718.083 |
| `binary_search` | 14093.637 | 12430.148 | 13440.243 | **12398.834** | 14975.113 | 13964.046 |
| `sort_window` | 11663.586 | 12290.780 | 8585.694 | 8222.141 | 8563.014 | **7947.998** |
| `bloom_filter` | 3445.497 | **2579.830** | 3057.413 | 2765.845 | 3120.468 | 2589.696 |
| `hash_join` | 10638.080 | 8897.119 | **8572.478** | 9179.874 | 10894.743 | 9010.708 |
| `sieve` | **9819.802** | 10770.058 | 11253.808 | 10793.454 | 10591.860 | 9940.322 |
| `fib` | 10275.583 | 7057.442 | 10326.369 | 7051.725 | 9442.950 | **6668.956** |
| `collatz` | 7354.935 | 6644.412 | 7359.157 | 6597.623 | 7329.094 | **6445.988** |
| `matmul` | 4361.964 | 4369.546 | **4210.166** | 4456.434 | 4416.611 | 4305.758 |
| `json_parse` | 2447.148 | 2445.476 | 1497.688 | **1130.194** | 2246.929 | 2288.335 |
| `nbody` | 8578.349 | 8430.354 | **7901.185** | 8044.220 | 8079.251 | 8388.272 |
| `safe_record_array` | 23289.686 | 23705.985 | **18962.778** | 20292.437 | 19308.563 | 20245.494 |
| `payload_state_machine` | 46860.726 | 49727.885 | 32782.025 | **30966.612** | 31208.976 | 31479.025 |
| `captured_closure_queue` | 47890.637 | 47036.980 | **41368.925** | 42703.264 | 44448.917 | 45430.946 |
| `dynamic_method_mix` | 50379.230 | 55387.711 | **47390.923** | 54177.269 | 48480.262 | 53312.841 |
| `csv_table_pipeline` | 36705.730 | 33696.158 | 28820.162 | 27170.201 | 27708.966 | **26829.851** |
| `chacha20` | 8138.760 | **8104.201** | 10102.553 | 10809.867 | 10098.250 | 10399.756 |
| `poly1305` | 21002.388 | 16100.235 | 20665.990 | **14751.761** | 25107.036 | 15016.350 |
| `blake2b` | 10927.153 | **10807.650** | 14082.526 | 16185.302 | 20823.724 | 19767.725 |
| `sha512` | **12905.083** | 13752.127 | 14296.018 | 15003.445 | 13284.315 | 14331.511 |
| `x25519` | 56557.782 | 33202.855 | 65252.757 | 33143.978 | 80707.358 | **32754.655** |

`nwasm` is faster than the reference runtime on 18 of 25 NURL modules,
14 of 25 C modules and 17 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.212_ | _0.4_ | _1.7_ | _0.6_ | _0.1_ |
| `lcg` | 10136.533 | 1.0 | 1.0 | 1.0 | 1.0 |
| `packet_classifier` | 12777.324 | 1.0 | 0.8 | 1.0 | 1.0 |
| `ring_write` | 11576.141 | 0.8 | 1.0 | 0.8 | 0.8 |
| `histogram_bins` | 10530.720 | 0.8 | 1.0 | 0.9 | 0.8 |
| `prefix_scan` | 1712.699 | 0.9 | 0.3 | 1.0 | 0.9 |
| `binary_search` | 12430.148 | 0.9 | 1.8 | 0.9 | 0.9 |
| `sort_window` | 12290.780 | 1.1 | 1.2 | 1.0 | 0.9 |
| `bloom_filter` | 2579.830 | 0.7 | 0.8 | 0.9 | 0.8 |
| `hash_join` | 8897.119 | 0.8 | 1.5 | 1.1 | 0.8 |
| `sieve` | 10770.058 | 1.1 | 1.2 | 1.0 | 0.9 |
| `fib` | 7057.442 | 0.7 | 1.0 | 0.7 | 0.7 |
| `collatz` | 6644.412 | 0.9 | 1.1 | 0.9 | 0.9 |
| `matmul` | 4369.546 | 1.0 | 0.9 | 1.1 | 1.0 |
| `json_parse` | 2445.476 | 1.0 | 2.5 | 0.8 | 1.0 |
| `nbody` | 8430.354 | 1.0 | 1.0 | 1.0 | 1.0 |
| `safe_record_array` | 23705.985 | 1.0 | 1.3 | 1.1 | 1.0 |
| `payload_state_machine` | 49727.885 | 1.1 | 2.2 | 0.9 | 1.0 |
| `captured_closure_queue` | 47036.980 | 1.0 | 1.7 | 1.0 | 1.0 |
| `dynamic_method_mix` | 55387.711 | 1.1 | 1.8 | 1.1 | 1.1 |
| `csv_table_pipeline` | 33696.158 | 0.9 | 2.0 | 0.9 | 1.0 |
| `chacha20` | 8104.201 | 1.0 | 9.5 | 1.1 | 1.0 |
| `poly1305` | 16100.235 | 0.8 | 7.1 | 0.7 | 0.6 |
| `blake2b` | 10807.650 | 1.0 | 1.0 | 1.1 | 0.9 |
| `sha512` | 13752.127 | 1.1 | 1.3 | 1.0 | 1.1 |
| `x25519` | 33202.855 | 0.6 | 4.7 | 0.5 | 0.4 |

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
| `lcg` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `packet_classifier` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `ring_write` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `histogram_bins` | 11 | 25 | 6 | 930 | 4388 | 2137 |
| `prefix_scan` | 11 | 25 | 6 | 931 | 4388 | 2138 |
| `binary_search` | 12 | 25 | 7 | 931 | 4389 | 2138 |
| `sort_window` | 11 | 25 | 6 | 931 | 4388 | 2138 |
| `bloom_filter` | 11 | 25 | 6 | 931 | 4388 | 2137 |
| `hash_join` | 18 | 27 | 8 | 938 | 4390 | 2140 |
| `sieve` | 11 | 25 | 7 | 931 | 4388 | 2137 |
| `fib` | 11 | 25 | 6 | 930 | 4387 | 2137 |
| `collatz` | 11 | 25 | 6 | 930 | 4387 | 2137 |
| `matmul` | 12 | 25 | 7 | 931 | 4389 | 2138 |
| `json_parse` | 35 | 44 | 10 | 1021 | 4402 | 2168 |
| `nbody` | 13 | 27 | 8 | 934 | 4389 | 2138 |
| `safe_record_array` | 28 | 34 | 7 | 933 | 4389 | 2139 |
| `payload_state_machine` | 21 | 31 | 7 | 936 | 4390 | 2139 |
| `captured_closure_queue` | 34 | 36 | 9 | 939 | 4395 | 2142 |
| `dynamic_method_mix` | 33 | 35 | 9 | 937 | 4393 | 2141 |
| `csv_table_pipeline` | 64 | 68 | 17 | 965 | 4400 | 2148 |
| `chacha20` | 40 | 37 | 7 | 937 | 4389 | 2138 |
| `poly1305` | 34 | 33 | 7 | 935 | 4389 | 2138 |
| `blake2b` | 34 | 40 | 9 | 940 | 4391 | 2140 |
| `sha512` | 32 | 39 | 8 | 936 | 4390 | 2139 |
| `x25519` | 41 | 46 | 39 | 1176 | 4421 | 2192 |

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
| _(floor: empty program)_ | _4_ | _366_ | _+9308 %_ | _11.056_ | _132.792_ | _+1101 %_ |
| `lcg` | 25 | 366 | +1371 % | 10222.788 | 10265.540 | +0 % |
| `packet_classifier` | 25 | 366 | +1373 % | 12841.368 | 13090.164 | +2 % |
| `ring_write` | 25 | 366 | +1370 % | 13667.862 | 13776.152 | +1 % |
| `histogram_bins` | 25 | 366 | +1366 % | 12503.448 | 12619.792 | +1 % |
| `prefix_scan` | 25 | 366 | +1349 % | 1891.700 | 2000.942 | +6 % |
| `binary_search` | 25 | 366 | +1363 % | 14093.637 | 14234.347 | +1 % |
| `sort_window` | 25 | 367 | +1350 % | 11663.586 | 11135.451 | −5 % |
| `bloom_filter` | 25 | 366 | +1357 % | 3445.497 | 3529.936 | +2 % |
| `hash_join` | 27 | 369 | +1266 % | 10638.080 | 10715.818 | +1 % |
| `sieve` | 25 | 366 | +1367 % | 9819.802 | 11071.710 | +13 % |
| `fib` | 25 | 366 | +1373 % | 10275.583 | 10413.802 | +1 % |
| `collatz` | 25 | 366 | +1374 % | 7354.935 | 7309.402 | −1 % |
| `matmul` | 25 | 366 | +1352 % | 4361.964 | 4499.768 | +3 % |
| `json_parse` | 44 | 380 | +754 % | 2447.148 | 2620.660 | +7 % |
| `nbody` | 27 | 368 | +1275 % | 8578.349 | 8731.261 | +2 % |
| `safe_record_array` | 34 | 369 | +985 % | 23289.686 | 23587.637 | +1 % |
| `payload_state_machine` | 31 | 369 | +1081 % | 46860.726 | 46763.830 | −0 % |
| `captured_closure_queue` | 36 | 371 | +919 % | 47890.637 | 47287.479 | −1 % |
| `dynamic_method_mix` | 35 | 371 | +949 % | 50379.230 | 50136.182 | −0 % |
| `csv_table_pipeline` | 68 | 390 | +478 % | 36705.730 | 36411.879 | −1 % |
| `chacha20` | 37 | 442 | +1090 % | 8138.760 | 8365.103 | +3 % |
| `poly1305` | 33 | 407 | +1145 % | 21002.388 | 21199.687 | +1 % |
| `blake2b` | 40 | 378 | +841 % | 10927.153 | 11102.217 | +2 % |
| `sha512` | 39 | 376 | +868 % | 12905.083 | 13404.977 | +4 % |
| `x25519` | 46 | 398 | +763 % | 56557.782 | 56352.826 | −0 % |

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
| _(floor: empty program)_ | _5.189_ | _59.373_ | _48.201_ | _22.796_ | _28.504_ | _41.953_ | _52.789_ |
| `lcg` | 5.717 | 67.991 | 51.251 | 26.064 | 28.293 | 47.621 | 59.977 |
| `packet_classifier` | 6.071 | 69.477 | 50.403 | 26.392 | 38.696 | 48.396 | 60.704 |
| `ring_write` | 11.413 | 77.134 | 63.470 | 28.053 | 28.836 | 49.555 | 62.032 |
| `histogram_bins` | 11.694 | 78.415 | 66.646 | 30.755 | 28.969 | 56.651 | 63.499 |
| `prefix_scan` | 11.531 | 80.430 | 64.110 | 30.356 | 28.955 | 52.623 | 64.690 |
| `binary_search` | 11.320 | 77.105 | 61.673 | 26.186 | 27.952 | 52.705 | 62.953 |
| `sort_window` | 11.243 | 79.797 | 67.636 | 31.305 | 30.247 | 55.536 | 69.993 |
| `bloom_filter` | 12.432 | 83.857 | 70.100 | 31.831 | 29.445 | 55.563 | 67.134 |
| `hash_join` | 15.610 | 138.140 | 112.915 | 54.804 | 30.160 | 85.152 | 98.232 |
| `sieve` | 11.848 | 80.580 | 68.725 | 33.745 | 29.045 | 61.088 | 70.802 |
| `fib` | 6.082 | 71.753 | 52.007 | 28.218 | 29.698 | 52.164 | 64.576 |
| `collatz` | 6.013 | 71.079 | 55.064 | 27.240 | 29.446 | 49.131 | 63.312 |
| `matmul` | 12.110 | 84.834 | 68.132 | 34.933 | 30.168 | 67.093 | 79.158 |
| `json_parse` | 40.991 | 295.486 | 258.618 | 59.524 | 30.362 | 147.276 | 128.801 |
| `nbody` | 13.366 | 88.723 | 83.842 | 46.251 | 30.633 | 70.967 | 84.153 |
| `safe_record_array` | 15.118 | 187.471 | 108.647 | 34.400 | 29.163 | 71.542 | 81.399 |
| `payload_state_machine` | 23.269 | 160.971 | 116.677 | 37.238 | 29.778 | 72.766 | 84.420 |
| `captured_closure_queue` | 18.378 | 226.761 | 121.546 | 41.053 | 28.004 | 96.657 | 97.651 |
| `dynamic_method_mix` | 17.954 | 222.294 | 122.327 | 40.743 | 29.363 | 88.963 | 92.152 |
| `csv_table_pipeline` | 73.862 | 524.658 | 434.630 | 123.736 | 29.331 | 214.961 | 218.600 |
| `chacha20` | 53.405 | 447.304 | 618.427 | 50.518 | 28.480 | 83.237 | 93.862 |
| `poly1305` | 44.480 | 318.417 | 309.920 | 56.085 | 28.106 | 102.037 | 100.086 |
| `blake2b` | 29.888 | 287.371 | 218.327 | 50.465 | 29.526 | 99.628 | 104.573 |
| `sha512` | 28.864 | 314.619 | 191.165 | 43.687 | 28.717 | 82.981 | 93.238 |
| `x25519` | 41.167 | 1123.262 | 686.449 | 469.451 | 29.838 | 527.822 | 533.701 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-1226497962176115656` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `2462986371` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `5626421774843711691` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `7370756466` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `3281681685` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `2207568789` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `5465279453` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `705779661` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `0` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `199373700` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `2768239500` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `704` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `117964714` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `6000` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595259552488757381` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `safe_record_array` | `5653786785231687554` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `payload_state_machine` | `2032895883230250981` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `captured_closure_queue` | `5692881218510219471` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `dynamic_method_mix` | `8717292098921376902` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `csv_table_pipeline` | `358538211080478995` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `chacha20` | `6829235544412143774` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `3185392352052989010` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `2447936398681434931` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sha512` | `5721417887030972397` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `x25519` | `6447182163740088706` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
