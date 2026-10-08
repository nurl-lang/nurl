# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-08T10:24:37Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372436 KiB |
| Commit | `d0e92dbc95817bd13ab3befca48321f602fdb821` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37761844503 |
| NURL | `v0.71.0-7-gd0e92dbc` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.3), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.3.0 (pure NURL)) — register-allocating JIT, template JIT and interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.229_ | _11.169_ | _9.1_ | _1.349_ | _6.104_ | _4.5_ | _1.393_ | _34.044_ | _24.4_ |
| `lcg` | 359.096 | 385.480 | 1.1 | 359.182 | 401.536 | 1.1 | 359.397 | 416.910 | 1.2 |
| `packet_classifier` | 510.643 | 495.935 | 1.0 | 509.460 | 495.043 | 1.0 | 510.984 | 500.670 | 1.0 |
| `ring_write` | 389.178 | 488.269 | 1.3 | 388.968 | 487.055 | 1.3 | 391.750 | 494.120 | 1.3 |
| `histogram_bins` | 390.944 | 480.647 | 1.2 | 393.836 | 485.781 | 1.2 | 368.956 | 488.175 | 1.3 |
| `prefix_scan` | 199.024 | 101.330 | 0.5 | 201.848 | 104.998 | 0.5 | 193.017 | 108.888 | 0.6 |
| `binary_search` | 281.216 | 620.294 | 2.2 | 280.795 | 631.648 | 2.2 | 378.195 | 657.127 | 1.7 |
| `sort_window` | 359.244 | 426.567 | 1.2 | 440.991 | 335.095 | 0.8 | 340.950 | 342.201 | 1.0 |
| `bloom_filter` | 125.678 | 179.822 | 1.4 | 128.646 | 162.437 | 1.3 | 123.519 | 166.521 | 1.3 |
| `hash_join` | 244.058 | 385.552 | 1.6 | 262.671 | 441.447 | 1.7 | 269.033 | 421.934 | 1.6 |
| `sieve` | 310.583 | 392.847 | 1.3 | 308.763 | 380.160 | 1.2 | 305.217 | 389.731 | 1.3 |
| `fib` | 242.449 | 408.646 | 1.7 | 250.669 | 389.934 | 1.6 | 236.414 | 391.994 | 1.7 |
| `collatz` | 138.443 | 257.096 | 1.9 | 137.528 | 263.659 | 1.9 | 136.401 | 264.472 | 1.9 |
| `matmul` | 152.917 | 173.775 | 1.1 | 153.009 | 175.783 | 1.1 | 152.859 | 181.268 | 1.2 |
| `json_parse` | 63.715 | 181.148 | 2.8 | 61.681 | 101.495 | 1.6 | 80.560 | 158.748 | 2.0 |
| `nbody` | 344.886 | 413.090 | 1.2 | 344.138 | 370.416 | 1.1 | 315.664 | 390.449 | 1.2 |
| `chacha20` | 199.227 | 410.385 | 2.1 | 364.716 | 449.829 | 1.2 | 367.680 | 478.308 | 1.3 |
| `poly1305` | 419.420 | 1945.657 | 4.6 | 392.183 | 2027.604 | 5.2 | 421.876 | 2608.575 | 6.2 |
| `blake2b` | 2388.572 | 6419.020 | 2.7 | 567.881 | 699.402 | 1.2 | 644.124 | 896.727 | 1.4 |
| `sha512` | 476.103 | 611.116 | 1.3 | 468.687 | 617.249 | 1.3 | 473.781 | 581.197 | 1.2 |
| `x25519` | 528.371 | 3073.051 | 5.8 | 494.757 | 3098.526 | 6.3 | 491.655 | 4009.293 | 8.2 |

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
| `lcg` | 1.0 | 1.0 | 1.1 | 1.1 |
| `packet_classifier` | 1.0 | 0.9 | 1.0 | 0.9 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.2 |
| `histogram_bins` | 1.2 | 1.2 | 1.2 | 1.2 |
| `prefix_scan` | 0.5 | — | 0.5 | 0.4 |
| `binary_search` | 2.2 | 2.1 | 2.2 | 1.7 |
| `sort_window` | 1.2 | 1.0 | 0.7 | 0.9 |
| `bloom_filter` | 1.4 | — | 1.2 | 1.1 |
| `hash_join` | 1.5 | 1.5 | 1.7 | 1.4 |
| `sieve` | 1.2 | 1.2 | 1.2 | 1.2 |
| `fib` | 1.6 | 1.5 | 1.5 | 1.5 |
| `collatz` | 1.8 | 1.6 | 1.9 | 1.7 |
| `matmul` | 1.1 | — | 1.1 | 1.0 |
| `json_parse` | 2.7 | 2.5 | 1.6 | 1.6 |
| `nbody` | 1.2 | 1.1 | 1.1 | 1.1 |
| `chacha20` | 2.0 | 1.9 | 1.2 | 1.2 |
| `poly1305` | 4.6 | 4.5 | 5.2 | 6.1 |
| `blake2b` | 2.7 | 2.7 | 1.2 | 1.3 |
| `sha512` | 1.3 | 1.2 | 1.3 | 1.2 |
| `x25519` | 5.8 | 6.0 | 6.3 | 8.1 |

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
| _(floor: empty program)_ | _11.169_ | _3.311_ | _6.104_ | _**2.483**_ | _34.044_ | _3.466_ |
| `lcg` | 385.480 | **364.389** | 401.536 | 368.113 | 416.910 | 367.730 |
| `packet_classifier` | 495.935 | 472.252 | 495.043 | 468.151 | 500.670 | **455.087** |
| `ring_write` | 488.269 | **404.316** | 487.055 | 405.315 | 494.120 | 405.152 |
| `histogram_bins` | 480.647 | 402.368 | 485.781 | 391.128 | 488.175 | **389.817** |
| `prefix_scan` | 101.330 | **74.954** | 104.998 | 76.856 | 108.888 | 77.903 |
| `binary_search` | 620.294 | **547.062** | 631.648 | 548.281 | 657.127 | 591.513 |
| `sort_window` | 426.567 | 412.236 | **335.095** | 352.633 | 342.201 | 349.026 |
| `bloom_filter` | 179.822 | **124.107** | 162.437 | 133.608 | 166.521 | 141.165 |
| `hash_join` | **385.552** | 389.289 | 441.447 | 426.294 | 421.934 | 405.195 |
| `sieve` | 392.847 | **337.909** | 380.160 | 372.562 | 389.731 | 349.308 |
| `fib` | 408.646 | 357.380 | 389.934 | 322.474 | 391.994 | **281.179** |
| `collatz` | 257.096 | **209.012** | 263.659 | 212.494 | 264.472 | 214.113 |
| `matmul` | 173.775 | 150.415 | 175.783 | 161.656 | 181.268 | **133.629** |
| `json_parse` | 181.148 | 169.515 | 101.495 | **68.479** | 158.748 | 119.945 |
| `nbody` | 413.090 | 420.966 | 370.416 | **351.805** | 390.449 | 368.183 |
| `chacha20` | **410.385** | 435.823 | 449.829 | 612.732 | 478.308 | 622.893 |
| `poly1305` | 1945.657 | **1677.479** | 2027.604 | 1687.697 | 2608.575 | 1935.080 |
| `blake2b` | 6419.020 | 4723.929 | **699.402** | 842.649 | 896.727 | 1094.456 |
| `sha512` | 611.116 | 754.432 | 617.249 | 764.779 | **581.197** | 740.862 |
| `x25519` | 3073.051 | **2813.692** | 3098.526 | 2913.921 | 4009.293 | 3195.168 |

`nwasm` is faster than the reference runtime on 16 of 20 NURL modules,
16 of 20 C modules and 16 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.311_ | _0.3_ | _2.7_ | _0.4_ | _0.1_ |
| `lcg` | 364.389 | 0.9 | 1.0 | 0.9 | 0.9 |
| `packet_classifier` | 472.252 | 1.0 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 404.316 | 0.8 | 1.0 | 0.8 | 0.8 |
| `histogram_bins` | 402.368 | 0.8 | 1.0 | 0.8 | 0.8 |
| `prefix_scan` | 74.954 | 0.7 | 0.4 | 0.7 | 0.7 |
| `binary_search` | 547.062 | 0.9 | 1.9 | 0.9 | 0.9 |
| `sort_window` | 412.236 | 1.0 | 1.1 | 1.1 | 1.0 |
| `bloom_filter` | 124.107 | 0.7 | 1.0 | 0.8 | 0.8 |
| `hash_join` | 389.289 | 1.0 | 1.6 | 1.0 | 1.0 |
| `sieve` | 337.909 | 0.9 | 1.1 | 1.0 | 0.9 |
| `fib` | 357.380 | 0.9 | 1.5 | 0.8 | 0.7 |
| `collatz` | 209.012 | 0.8 | 1.5 | 0.8 | 0.8 |
| `matmul` | 150.415 | 0.9 | 1.0 | 0.9 | 0.7 |
| `json_parse` | 169.515 | 0.9 | 2.7 | 0.7 | 0.8 |
| `nbody` | 420.966 | 1.0 | 1.2 | 0.9 | 0.9 |
| `chacha20` | 435.823 | 1.1 | 2.2 | 1.4 | 1.3 |
| `poly1305` | 1677.479 | 0.9 | 4.0 | 0.8 | 0.7 |
| `blake2b` | 4723.929 | 0.7 | 2.0 | 1.2 | 1.2 |
| `sha512` | 754.432 | 1.2 | 1.6 | 1.2 | 1.3 |
| `x25519` | 2813.692 | 0.9 | 5.3 | 0.9 | 0.8 |

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
| `chacha20` | 31 | 46 | 16 | 923 | 4432 | 2129 |
| `poly1305` | 27 | 32 | 16 | 922 | 4433 | 2130 |
| `blake2b` | 32 | 38 | 16 | 925 | 4434 | 2132 |
| `sha512` | 31 | 37 | 16 | 922 | 4433 | 2130 |
| `x25519` | 35 | 42 | 48 | 1161 | 4464 | 2183 |

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
| _(floor: empty program)_ | _4_ | _311_ | _+7715 %_ | _11.169_ | _151.520_ | _+1257 %_ |
| `lcg` | 26 | 311 | +1087 % | 385.480 | 503.342 | +31 % |
| `packet_classifier` | 26 | 311 | +1090 % | 495.935 | 615.266 | +24 % |
| `ring_write` | 26 | 311 | +1087 % | 488.269 | 604.964 | +24 % |
| `histogram_bins` | 26 | 311 | +1084 % | 480.647 | 600.771 | +25 % |
| `prefix_scan` | 27 | 311 | +1071 % | 101.330 | 218.004 | +115 % |
| `binary_search` | 26 | 311 | +1082 % | 620.294 | 747.793 | +21 % |
| `sort_window` | 27 | 312 | +1073 % | 426.567 | 514.056 | +21 % |
| `bloom_filter` | 26 | 312 | +1078 % | 179.822 | 297.682 | +66 % |
| `hash_join` | 28 | 314 | +1009 % | 385.552 | 508.527 | +32 % |
| `sieve` | 26 | 311 | +1085 % | 392.847 | 517.255 | +32 % |
| `fib` | 26 | 311 | +1083 % | 408.646 | 505.698 | +24 % |
| `collatz` | 26 | 311 | +1091 % | 257.096 | 368.050 | +43 % |
| `matmul` | 27 | 311 | +1074 % | 173.775 | 295.818 | +70 % |
| `json_parse` | 50 | 331 | +561 % | 181.148 | 307.502 | +70 % |
| `nbody` | 28 | 313 | +1016 % | 413.090 | 539.294 | +31 % |
| `chacha20` | 46 | 331 | +621 % | 410.385 | 524.761 | +28 % |
| `poly1305` | 32 | 315 | +870 % | 1945.657 | 2052.600 | +5 % |
| `blake2b` | 38 | 322 | +743 % | 6419.020 | 6516.540 | +2 % |
| `sha512` | 37 | 320 | +768 % | 611.116 | 715.019 | +17 % |
| `x25519` | 42 | 326 | +681 % | 3073.051 | 3314.935 | +8 % |

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
| _(floor: empty program)_ | _3.444_ | _94.144_ | _41.116_ | _52.420_ | _34.196_ | _58.131_ | _70.431_ |
| `lcg` | 3.403 | 110.661 | 43.242 | 61.316 | 34.900 | 69.274 | 85.521 |
| `packet_classifier` | 3.438 | 110.569 | 43.377 | 62.537 | 35.299 | 67.233 | 78.952 |
| `ring_write` | 3.626 | 111.082 | 43.232 | 62.048 | 34.557 | 67.116 | 80.134 |
| `histogram_bins` | 3.786 | 116.448 | 44.062 | 64.471 | 34.857 | 70.261 | 82.361 |
| `prefix_scan` | 3.724 | 116.326 | 43.021 | 65.894 | 34.498 | 68.049 | 81.704 |
| `binary_search` | 3.973 | 115.280 | 43.838 | 62.850 | 34.085 | 72.453 | 83.408 |
| `sort_window` | 4.156 | 122.028 | 44.376 | 69.567 | 35.366 | 77.268 | 89.095 |
| `bloom_filter` | 4.512 | 122.734 | 45.169 | 69.514 | 35.066 | 75.676 | 84.097 |
| `hash_join` | 7.945 | 222.621 | 57.978 | 107.117 | 34.494 | 109.229 | 119.257 |
| `sieve` | 4.161 | 118.418 | 44.546 | 72.353 | 35.121 | 80.333 | 88.462 |
| `fib` | 3.613 | 112.751 | 43.564 | 62.449 | 34.989 | 68.068 | 79.562 |
| `collatz` | 3.686 | 112.458 | 42.777 | 61.784 | 35.189 | 64.926 | 80.164 |
| `matmul` | 5.206 | 122.531 | 45.019 | 73.363 | 34.838 | 87.826 | 95.974 |
| `json_parse` | 43.716 | 604.692 | 123.433 | 111.669 | 35.731 | 170.048 | 147.974 |
| `nbody` | 6.221 | 131.000 | 52.197 | 87.531 | 34.452 | 89.943 | 99.435 |
| `chacha20` | 35.082 | 413.835 | 122.600 | 100.474 | 34.974 | 112.387 | 119.748 |
| `poly1305` | 21.097 | 282.558 | 73.905 | 111.648 | 34.473 | 127.606 | 129.441 |
| `blake2b` | 33.685 | 362.970 | 96.266 | 103.266 | 34.860 | 124.920 | 129.582 |
| `sha512` | 29.781 | 344.899 | 92.407 | 88.202 | 34.347 | 106.148 | 115.291 |
| `x25519` | 35.699 | 434.491 | 108.589 | 746.762 | 35.149 | 626.445 | 624.865 |

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
