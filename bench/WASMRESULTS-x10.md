# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-14T04:56:28Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-x10.json`](results/wasm-x10.json).

**Workload ×10.** Every benchmark below does 10 times its published
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
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `ede65cf52ce96593ff73d62343a11d24a1a5081d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/43557737570 |
| NURL | `v0.91.1-118-gede65cf5` |
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
| Workload scale | ×10 — every benchmark's work multiplied by 10 before compilation |
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
| _(floor: empty program)_ | _2.953_ | _10.232_ | _3.5_ | _2.947_ | _7.917_ | _2.7_ | _3.079_ | _29.711_ | _9.6_ |
| `lcg` | 331.082 | 350.768 | 1.1 | 330.972 | 351.504 | 1.1 | 331.104 | 357.423 | 1.1 |
| `packet_classifier` | 481.109 | 466.204 | 1.0 | 480.902 | 467.250 | 1.0 | 480.941 | 473.234 | 1.0 |
| `ring_write` | 358.259 | 459.431 | 1.3 | 358.270 | 460.635 | 1.3 | 358.398 | 465.971 | 1.3 |
| `histogram_bins` | 334.963 | 483.951 | 1.4 | 335.033 | 419.757 | 1.3 | 335.019 | 439.928 | 1.3 |
| `prefix_scan` | 180.024 | 98.519 | 0.5 | 179.930 | 96.467 | 0.5 | 179.934 | 106.945 | 0.6 |
| `binary_search` | 250.776 | 500.209 | 2.0 | 252.685 | 526.494 | 2.1 | 359.933 | 527.228 | 1.5 |
| `sort_window` | 227.627 | 339.273 | 1.5 | 518.901 | 293.486 | 0.6 | 222.030 | 288.505 | 1.3 |
| `bloom_filter` | 123.881 | 156.886 | 1.3 | 148.284 | 162.644 | 1.1 | 148.298 | 157.813 | 1.1 |
| `hash_join` | 195.977 | 338.467 | 1.7 | 226.073 | 321.930 | 1.4 | 227.266 | 345.043 | 1.5 |
| `sieve` | 143.031 | 194.006 | 1.4 | 142.831 | 233.133 | 1.6 | 142.543 | 236.662 | 1.7 |
| `fib` | 215.670 | 360.957 | 1.7 | 246.535 | 361.369 | 1.5 | 246.550 | 340.979 | 1.4 |
| `collatz` | 115.396 | 204.855 | 1.8 | 115.267 | 206.624 | 1.8 | 115.426 | 212.228 | 1.8 |
| `matmul` | 339.806 | 314.541 | 0.9 | 340.639 | 262.136 | 0.8 | 340.711 | 252.979 | 0.7 |
| `json_parse` | 33.422 | 123.615 | 3.7 | 79.156 | 73.954 | 0.9 | 119.656 | 128.495 | 1.1 |
| `nbody` | 347.020 | 362.086 | 1.0 | 375.831 | 357.913 | 1.0 | 328.875 | 361.987 | 1.1 |
| `safe_record_array` | 521.997 | 729.554 | 1.4 | 457.840 | 599.945 | 1.3 | 551.232 | 595.180 | 1.1 |
| `payload_state_machine` | 650.324 | 1554.739 | 2.4 | 615.587 | 912.283 | 1.5 | 626.416 | 909.131 | 1.5 |
| `captured_closure_queue` | 906.608 | 1402.733 | 1.5 | 708.798 | 1240.656 | 1.8 | 834.874 | 1313.659 | 1.6 |
| `dynamic_method_mix` | 1042.183 | 1745.650 | 1.7 | 1063.432 | 1608.840 | 1.5 | 995.673 | 1682.209 | 1.7 |
| `csv_table_pipeline` | 540.041 | 1112.850 | 2.1 | 774.644 | 996.809 | 1.3 | 506.544 | 841.320 | 1.7 |
| `chacha20` | 35.491 | 340.868 | 9.6 | 313.124 | 383.429 | 1.2 | 341.635 | 389.871 | 1.1 |
| `poly1305` | 97.144 | 913.983 | 9.4 | 173.377 | 879.400 | 5.1 | 173.681 | 1073.469 | 6.2 |
| `blake2b` | 357.881 | 413.974 | 1.2 | 559.106 | 654.815 | 1.2 | 597.211 | 789.140 | 1.3 |
| `sha512` | 376.431 | 485.422 | 1.3 | 400.806 | 493.201 | 1.2 | 406.072 | 505.161 | 1.2 |
| `x25519` | 269.234 | 2207.305 | 8.2 | 473.786 | 2752.690 | 5.8 | 446.205 | 3549.831 | 8.0 |

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
| `packet_classifier` | 1.0 | 0.9 | 1.0 | 0.9 |
| `ring_write` | 1.3 | 1.2 | 1.3 | 1.2 |
| `histogram_bins` | 1.4 | 1.4 | 1.2 | 1.2 |
| `prefix_scan` | 0.5 | — | 0.5 | 0.4 |
| `binary_search` | 2.0 | 2.0 | 2.1 | 1.4 |
| `sort_window` | 1.5 | 1.4 | 0.6 | 1.2 |
| `bloom_filter` | 1.2 | 1.1 | 1.1 | 0.9 |
| `hash_join` | 1.7 | 1.7 | 1.4 | 1.4 |
| `sieve` | 1.3 | 1.5 | 1.6 | 1.5 |
| `fib` | 1.6 | 1.6 | 1.5 | 1.3 |
| `collatz` | 1.7 | 1.6 | 1.8 | 1.6 |
| `matmul` | 0.9 | 0.9 | 0.8 | 0.7 |
| `json_parse` | 3.7 | — | 0.9 | 0.8 |
| `nbody` | 1.0 | 1.0 | 0.9 | 1.0 |
| `safe_record_array` | 1.4 | 1.4 | 1.3 | 1.0 |
| `payload_state_machine` | 2.4 | 2.4 | 1.5 | 1.4 |
| `captured_closure_queue` | 1.5 | 1.5 | 1.7 | 1.5 |
| `dynamic_method_mix` | 1.7 | 1.6 | 1.5 | 1.7 |
| `csv_table_pipeline` | 2.1 | 2.0 | 1.3 | 1.6 |
| `chacha20` | 10.2 | 10.4 | 1.2 | 1.1 |
| `poly1305` | 9.6 | 9.6 | 5.1 | 6.1 |
| `blake2b` | 1.1 | 1.1 | 1.2 | 1.3 |
| `sha512` | 1.3 | 1.2 | 1.2 | 1.2 |
| `x25519` | 8.3 | 8.1 | 5.8 | 7.9 |

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
| _(floor: empty program)_ | _10.232_ | _4.743_ | _7.917_ | _**4.407**_ | _29.711_ | _5.495_ |
| `lcg` | 350.768 | **333.614** | 351.504 | 336.897 | 357.423 | 336.859 |
| `packet_classifier` | 466.204 | **415.809** | 467.250 | 418.844 | 473.234 | 419.177 |
| `ring_write` | 459.431 | **388.463** | 460.635 | 391.533 | 465.971 | 391.913 |
| `histogram_bins` | 483.951 | **346.904** | 419.757 | 359.065 | 439.928 | 350.173 |
| `prefix_scan` | 98.519 | **61.557** | 96.467 | 82.150 | 106.945 | 65.157 |
| `binary_search` | 500.209 | **406.523** | 526.494 | 410.463 | 527.228 | 444.140 |
| `sort_window` | 339.273 | 352.530 | 293.486 | 317.540 | **288.505** | 306.047 |
| `bloom_filter` | 156.886 | **115.669** | 162.644 | 118.757 | 157.813 | 120.334 |
| `hash_join` | 338.467 | **301.710** | 321.930 | 307.909 | 345.043 | 312.851 |
| `sieve` | 194.006 | 205.672 | 233.133 | 213.822 | 236.662 | **169.950** |
| `fib` | 360.957 | 247.422 | 361.369 | 246.374 | 340.979 | **238.572** |
| `collatz` | 204.855 | **187.093** | 206.624 | 190.215 | 212.228 | 190.744 |
| `matmul` | 314.541 | 260.922 | 262.136 | **192.150** | 252.979 | 197.812 |
| `json_parse` | 123.615 | 109.805 | 73.954 | **55.131** | 128.495 | 103.191 |
| `nbody` | 362.086 | 404.117 | 357.913 | **343.867** | 361.987 | 369.088 |
| `safe_record_array` | 729.554 | 749.054 | 599.945 | 612.153 | **595.180** | 616.245 |
| `payload_state_machine` | 1554.739 | 1623.060 | 912.283 | **881.668** | 909.131 | 895.131 |
| `captured_closure_queue` | 1402.733 | 1638.883 | 1240.656 | **1235.796** | 1313.659 | 1460.860 |
| `dynamic_method_mix` | 1745.650 | 1878.256 | **1608.840** | 1966.743 | 1682.209 | 2015.521 |
| `csv_table_pipeline` | 1112.850 | 1064.057 | 996.809 | 948.503 | 841.320 | **808.732** |
| `chacha20` | 340.868 | **317.364** | 383.429 | 392.340 | 389.871 | 400.476 |
| `poly1305` | 913.983 | 514.469 | 879.400 | **460.995** | 1073.469 | 476.016 |
| `blake2b` | **413.974** | 443.698 | 654.815 | 688.675 | 789.140 | 830.579 |
| `sha512` | 485.422 | **449.804** | 493.201 | 499.529 | 505.161 | 519.391 |
| `x25519` | 2207.305 | **1214.573** | 2752.690 | 1224.699 | 3549.831 | 1230.947 |

`nwasm` is faster than the reference runtime on 17 of 25 NURL modules,
19 of 25 C modules and 17 of 25 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _4.743_ | _0.5_ | _1.6_ | _0.6_ | _0.2_ |
| `lcg` | 333.614 | 1.0 | 1.0 | 1.0 | 0.9 |
| `packet_classifier` | 415.809 | 0.9 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 388.463 | 0.8 | 1.1 | 0.8 | 0.8 |
| `histogram_bins` | 346.904 | 0.7 | 1.0 | 0.9 | 0.8 |
| `prefix_scan` | 61.557 | 0.6 | 0.3 | 0.9 | 0.6 |
| `binary_search` | 406.523 | 0.8 | 1.6 | 0.8 | 0.8 |
| `sort_window` | 352.530 | 1.0 | 1.5 | 1.1 | 1.1 |
| `bloom_filter` | 115.669 | 0.7 | 0.9 | 0.7 | 0.8 |
| `hash_join` | 301.710 | 0.9 | 1.5 | 1.0 | 0.9 |
| `sieve` | 205.672 | 1.1 | 1.4 | 0.9 | 0.7 |
| `fib` | 247.422 | 0.7 | 1.1 | 0.7 | 0.7 |
| `collatz` | 187.093 | 0.9 | 1.6 | 0.9 | 0.9 |
| `matmul` | 260.922 | 0.8 | 0.8 | 0.7 | 0.8 |
| `json_parse` | 109.805 | 0.9 | 3.3 | 0.7 | 0.8 |
| `nbody` | 404.117 | 1.1 | 1.2 | 1.0 | 1.0 |
| `safe_record_array` | 749.054 | 1.0 | 1.4 | 1.0 | 1.0 |
| `payload_state_machine` | 1623.060 | 1.0 | 2.5 | 1.0 | 1.0 |
| `captured_closure_queue` | 1638.883 | 1.2 | 1.8 | 1.0 | 1.1 |
| `dynamic_method_mix` | 1878.256 | 1.1 | 1.8 | 1.2 | 1.2 |
| `csv_table_pipeline` | 1064.057 | 1.0 | 2.0 | 1.0 | 1.0 |
| `chacha20` | 317.364 | 0.9 | 8.9 | 1.0 | 1.0 |
| `poly1305` | 514.469 | 0.6 | 5.3 | 0.5 | 0.4 |
| `blake2b` | 443.698 | 1.1 | 1.2 | 1.1 | 1.1 |
| `sha512` | 449.804 | 0.9 | 1.2 | 1.0 | 1.0 |
| `x25519` | 1214.573 | 0.6 | 4.5 | 0.4 | 0.3 |

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
| _(floor: empty program)_ | _4_ | _366_ | _+9308 %_ | _10.232_ | _125.370_ | _+1125 %_ |
| `lcg` | 25 | 366 | +1369 % | 350.768 | 455.980 | +30 % |
| `packet_classifier` | 25 | 366 | +1373 % | 466.204 | 571.738 | +23 % |
| `ring_write` | 25 | 366 | +1370 % | 459.431 | 565.570 | +23 % |
| `histogram_bins` | 25 | 366 | +1366 % | 483.951 | 591.612 | +22 % |
| `prefix_scan` | 25 | 366 | +1349 % | 98.519 | 205.179 | +108 % |
| `binary_search` | 25 | 366 | +1363 % | 500.209 | 613.985 | +23 % |
| `sort_window` | 25 | 367 | +1350 % | 339.273 | 447.030 | +32 % |
| `bloom_filter` | 25 | 366 | +1357 % | 156.886 | 261.807 | +67 % |
| `hash_join` | 27 | 369 | +1266 % | 338.467 | 451.203 | +33 % |
| `sieve` | 25 | 366 | +1367 % | 194.006 | 336.546 | +73 % |
| `fib` | 25 | 366 | +1365 % | 360.957 | 455.087 | +26 % |
| `collatz` | 25 | 366 | +1374 % | 204.855 | 310.299 | +51 % |
| `matmul` | 25 | 366 | +1352 % | 314.541 | 413.114 | +31 % |
| `json_parse` | 44 | 380 | +754 % | 123.615 | 220.236 | +78 % |
| `nbody` | 27 | 368 | +1275 % | 362.086 | 478.484 | +32 % |
| `safe_record_array` | 34 | 369 | +985 % | 729.554 | 833.860 | +14 % |
| `payload_state_machine` | 31 | 369 | +1081 % | 1554.739 | 1648.090 | +6 % |
| `captured_closure_queue` | 36 | 371 | +919 % | 1402.733 | 1504.591 | +7 % |
| `dynamic_method_mix` | 35 | 371 | +949 % | 1745.650 | 1808.135 | +4 % |
| `csv_table_pipeline` | 68 | 390 | +478 % | 1112.850 | 1222.380 | +10 % |
| `chacha20` | 37 | 442 | +1090 % | 340.868 | 464.301 | +36 % |
| `poly1305` | 33 | 407 | +1145 % | 913.983 | 1030.318 | +13 % |
| `blake2b` | 40 | 378 | +841 % | 413.974 | 507.857 | +23 % |
| `sha512` | 39 | 376 | +868 % | 485.422 | 587.258 | +21 % |
| `x25519` | 46 | 398 | +763 % | 2207.305 | 2281.488 | +3 % |

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
| _(floor: empty program)_ | _6.282_ | _76.241_ | _60.890_ | _28.280_ | _36.954_ | _48.731_ | _61.005_ |
| `lcg` | 6.491 | 73.583 | 63.036 | 32.989 | 38.025 | 53.312 | 65.853 |
| `packet_classifier` | 6.540 | 74.359 | 63.406 | 33.707 | 37.763 | 54.066 | 65.390 |
| `ring_write` | 12.072 | 81.848 | 75.921 | 34.181 | 37.755 | 55.393 | 67.492 |
| `histogram_bins` | 12.191 | 84.074 | 78.356 | 36.058 | 37.147 | 57.062 | 68.020 |
| `prefix_scan` | 12.281 | 85.184 | 77.151 | 36.517 | 36.845 | 57.225 | 68.231 |
| `binary_search` | 12.474 | 84.412 | 75.963 | 34.596 | 37.555 | 58.333 | 70.439 |
| `sort_window` | 12.432 | 87.883 | 82.191 | 37.695 | 37.338 | 62.202 | 74.239 |
| `bloom_filter` | 12.793 | 86.907 | 83.129 | 37.393 | 38.216 | 59.036 | 70.758 |
| `hash_join` | 15.689 | 138.598 | 126.407 | 56.952 | 37.197 | 85.309 | 98.134 |
| `sieve` | 12.264 | 85.843 | 82.029 | 40.032 | 37.559 | 65.779 | 75.536 |
| `fib` | 6.609 | 75.047 | 63.397 | 34.230 | 39.104 | 55.268 | 66.527 |
| `collatz` | 6.715 | 74.918 | 66.553 | 33.702 | 37.432 | 54.881 | 66.868 |
| `matmul` | 12.567 | 89.034 | 80.352 | 41.050 | 61.211 | 72.898 | 81.937 |
| `json_parse` | 39.074 | 266.819 | 269.885 | 59.351 | 37.999 | 134.114 | 123.221 |
| `nbody` | 13.748 | 92.671 | 104.094 | 49.015 | 37.583 | 72.394 | 85.009 |
| `safe_record_array` | 15.299 | 177.473 | 112.673 | 41.057 | 38.088 | 79.955 | 84.917 |
| `payload_state_machine` | 23.038 | 154.968 | 132.318 | 43.631 | 37.345 | 77.215 | 85.128 |
| `captured_closure_queue` | 18.578 | 213.715 | 137.984 | 47.226 | 37.497 | 97.243 | 99.169 |
| `dynamic_method_mix` | 18.047 | 211.443 | 139.219 | 45.942 | 37.634 | 91.558 | 95.550 |
| `csv_table_pipeline` | 69.839 | 471.325 | 442.557 | 118.732 | 48.581 | 193.870 | 199.497 |
| `chacha20` | 56.248 | 431.837 | 633.010 | 56.002 | 38.547 | 89.533 | 99.165 |
| `poly1305` | 45.503 | 304.865 | 324.246 | 60.418 | 38.689 | 94.858 | 107.091 |
| `blake2b` | 29.894 | 274.180 | 212.610 | 55.170 | 37.703 | 99.050 | 106.211 |
| `sha512` | 28.767 | 294.823 | 206.725 | 50.419 | 37.664 | 89.566 | 96.474 |
| `x25519` | 41.670 | 1015.130 | 675.417 | 446.153 | 38.359 | 501.142 | 532.809 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-5686402545359347083` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `3079799295` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `7275473283115887719` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `277805545` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `1425077525` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `697754069` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `5836882087` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `23524607` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `0` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `6645790` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `92274650` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `524` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `3932099` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `200` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595259882203992578` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `safe_record_array` | `3218500468098587910` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `payload_state_machine` | `1110477258004986458` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `captured_closure_queue` | `5577643534544365594` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `dynamic_method_mix` | `1043857738373850969` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `csv_table_pipeline` | `2252685061690218411` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `chacha20` | `6549430722411435339` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `2872857361162037662` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `3765762126214486209` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sha512` | `2257795488829378650` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `x25519` | `348248275458593324` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
