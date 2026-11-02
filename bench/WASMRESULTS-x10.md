# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-11-02T08:32:23Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16365632 KiB |
| Commit | `38c8f6c8bc1c1b9f9e9772bbaaa70b49f166774c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41412263858 |
| NURL | `v0.84.0-13-g38c8f6c8` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
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
| _(floor: empty program)_ | _3.052_ | _12.146_ | _4.0_ | _3.182_ | _9.007_ | _2.8_ | _3.265_ | _32.800_ | _10.0_ |
| `lcg` | 361.597 | 386.011 | 1.1 | 361.360 | 409.837 | 1.1 | 361.335 | 397.735 | 1.1 |
| `packet_classifier` | 513.089 | 497.501 | 1.0 | 511.881 | 496.966 | 1.0 | 513.319 | 506.756 | 1.0 |
| `ring_write` | 391.822 | 490.312 | 1.3 | 391.253 | 490.870 | 1.3 | 394.084 | 496.789 | 1.3 |
| `histogram_bins` | 362.355 | 483.159 | 1.3 | 374.910 | 485.194 | 1.3 | 362.912 | 492.772 | 1.4 |
| `prefix_scan` | 195.292 | 107.281 | 0.5 | 191.680 | 118.102 | 0.6 | 195.009 | 110.370 | 0.6 |
| `binary_search` | 283.742 | 626.711 | 2.2 | 282.878 | 640.445 | 2.3 | 380.383 | 670.139 | 1.8 |
| `sort_window` | 366.086 | 470.676 | 1.3 | 758.258 | 335.209 | 0.4 | 343.350 | 344.281 | 1.0 |
| `bloom_filter` | 126.376 | 174.532 | 1.4 | 126.297 | 164.882 | 1.3 | 125.472 | 174.069 | 1.4 |
| `hash_join` | 231.471 | 446.250 | 1.9 | 262.433 | 441.294 | 1.7 | 270.888 | 423.272 | 1.6 |
| `sieve` | 343.892 | 460.153 | 1.3 | 341.185 | 408.314 | 1.2 | 316.117 | 389.998 | 1.2 |
| `fib` | 244.333 | 385.903 | 1.6 | 253.057 | 390.623 | 1.5 | 238.691 | 397.807 | 1.7 |
| `collatz` | 141.170 | 254.554 | 1.8 | 139.927 | 265.101 | 1.9 | 138.580 | 266.305 | 1.9 |
| `matmul` | 155.051 | 176.465 | 1.1 | 155.499 | 176.743 | 1.1 | 155.091 | 184.069 | 1.2 |
| `json_parse` | 42.133 | 141.552 | 3.4 | 81.201 | 94.912 | 1.2 | 114.583 | 148.530 | 1.3 |
| `nbody` | 346.191 | 415.005 | 1.2 | 345.861 | 372.395 | 1.1 | 318.212 | 393.881 | 1.2 |
| `chacha20` | 34.792 | 381.198 | 11.0 | 365.316 | 457.252 | 1.3 | 369.438 | 480.496 | 1.3 |
| `poly1305` | 85.662 | 996.987 | 11.6 | 242.073 | 994.675 | 4.1 | 241.870 | 1226.320 | 5.1 |
| `blake2b` | 436.062 | 592.899 | 1.4 | 565.163 | 699.169 | 1.2 | 648.672 | 893.999 | 1.4 |
| `sha512` | 437.402 | 587.205 | 1.3 | 446.309 | 624.822 | 1.4 | 475.790 | 583.477 | 1.2 |
| `x25519` | 295.906 | 2454.309 | 8.3 | 495.024 | 3117.749 | 6.3 | 494.780 | 4007.352 | 8.1 |

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
| `lcg` | 1.0 | 1.0 | 1.1 | 1.0 |
| `packet_classifier` | 1.0 | 0.9 | 1.0 | 0.9 |
| `ring_write` | 1.2 | 1.2 | 1.2 | 1.2 |
| `histogram_bins` | 1.3 | 1.3 | 1.3 | 1.3 |
| `prefix_scan` | 0.5 | — | 0.6 | 0.4 |
| `binary_search` | 2.2 | 2.1 | 2.3 | 1.7 |
| `sort_window` | 1.3 | 1.2 | 0.4 | 0.9 |
| `bloom_filter` | 1.3 | — | 1.3 | 1.2 |
| `hash_join` | 1.9 | 1.8 | 1.7 | 1.5 |
| `sieve` | 1.3 | 1.3 | 1.2 | 1.1 |
| `fib` | 1.5 | 1.5 | 1.5 | 1.6 |
| `collatz` | 1.8 | 1.5 | 1.9 | 1.7 |
| `matmul` | 1.1 | — | 1.1 | 1.0 |
| `json_parse` | 3.3 | — | 1.1 | 1.0 |
| `nbody` | 1.2 | 1.1 | 1.1 | 1.1 |
| `chacha20` | 11.6 | 12.2 | 1.2 | 1.2 |
| `poly1305` | 11.9 | 11.7 | 4.1 | 5.0 |
| `blake2b` | 1.3 | 1.3 | 1.2 | 1.3 |
| `sha512` | 1.3 | 1.3 | 1.4 | 1.2 |
| `x25519` | 8.3 | 8.4 | 6.3 | 8.1 |

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
| _(floor: empty program)_ | _12.146_ | _5.885_ | _9.007_ | _**4.916**_ | _32.800_ | _6.481_ |
| `lcg` | 386.011 | **367.152** | 409.837 | 370.740 | 397.735 | 370.451 |
| `packet_classifier` | 497.501 | 476.821 | 496.966 | **464.627** | 506.756 | 468.318 |
| `ring_write` | 490.312 | **406.578** | 490.870 | 409.074 | 496.789 | 408.753 |
| `histogram_bins` | 483.159 | 404.602 | 485.194 | **393.819** | 492.772 | 396.709 |
| `prefix_scan` | 107.281 | **77.176** | 118.102 | 78.668 | 110.370 | 81.096 |
| `binary_search` | 626.711 | 569.955 | 640.445 | **551.743** | 670.139 | 591.926 |
| `sort_window` | 470.676 | 420.104 | **335.209** | 352.417 | 344.281 | 350.377 |
| `bloom_filter` | 174.532 | **125.795** | 164.882 | 132.333 | 174.069 | 128.496 |
| `hash_join` | 446.250 | **384.974** | 441.294 | 433.305 | 423.272 | 392.061 |
| `sieve` | 460.153 | **345.156** | 408.314 | 358.384 | 389.998 | 374.832 |
| `fib` | 385.903 | 338.609 | 390.623 | 326.332 | 397.807 | **276.412** |
| `collatz` | 254.554 | **212.001** | 265.101 | 215.076 | 266.305 | 218.009 |
| `matmul` | 176.465 | 164.101 | 176.743 | 164.742 | 184.069 | **138.362** |
| `json_parse` | 141.552 | 123.220 | 94.912 | **71.850** | 148.530 | 131.188 |
| `nbody` | 415.005 | 419.163 | 372.395 | **348.805** | 393.881 | 370.949 |
| `chacha20` | 381.198 | **347.335** | 457.252 | 472.050 | 480.496 | 474.411 |
| `poly1305` | 996.987 | 643.120 | 994.675 | **586.795** | 1226.320 | 604.264 |
| `blake2b` | 592.899 | **521.784** | 699.169 | 713.428 | 893.999 | 965.363 |
| `sha512` | 587.205 | 627.191 | 624.822 | 605.428 | **583.477** | 633.995 |
| `x25519` | 2454.309 | **1392.605** | 3117.749 | 1556.277 | 4007.352 | 1562.778 |

`nwasm` is faster than the reference runtime on 18 of 20 NURL modules,
17 of 20 C modules and 17 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _5.885_ | _0.5_ | _1.9_ | _0.5_ | _0.2_ |
| `lcg` | 367.152 | 1.0 | 1.0 | 0.9 | 0.9 |
| `packet_classifier` | 476.821 | 1.0 | 0.9 | 0.9 | 0.9 |
| `ring_write` | 406.578 | 0.8 | 1.0 | 0.8 | 0.8 |
| `histogram_bins` | 404.602 | 0.8 | 1.1 | 0.8 | 0.8 |
| `prefix_scan` | 77.176 | 0.7 | 0.4 | 0.7 | 0.7 |
| `binary_search` | 569.955 | 0.9 | 2.0 | 0.9 | 0.9 |
| `sort_window` | 420.104 | 0.9 | 1.1 | 1.1 | 1.0 |
| `bloom_filter` | 125.795 | 0.7 | 1.0 | 0.8 | 0.7 |
| `hash_join` | 384.974 | 0.9 | 1.7 | 1.0 | 0.9 |
| `sieve` | 345.156 | 0.8 | 1.0 | 0.9 | 1.0 |
| `fib` | 338.609 | 0.9 | 1.4 | 0.8 | 0.7 |
| `collatz` | 212.001 | 0.8 | 1.5 | 0.8 | 0.8 |
| `matmul` | 164.101 | 0.9 | 1.1 | 0.9 | 0.8 |
| `json_parse` | 123.220 | 0.9 | 2.9 | 0.8 | 0.9 |
| `nbody` | 419.163 | 1.0 | 1.2 | 0.9 | 0.9 |
| `chacha20` | 347.335 | 0.9 | 10.0 | 1.0 | 1.0 |
| `poly1305` | 643.120 | 0.6 | 7.5 | 0.6 | 0.5 |
| `blake2b` | 521.784 | 0.9 | 1.2 | 1.0 | 1.1 |
| `sha512` | 627.191 | 1.1 | 1.4 | 1.0 | 1.1 |
| `x25519` | 1392.605 | 0.6 | 4.7 | 0.5 | 0.4 |

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
| `json_parse` | 37 | 46 | 16 | 1007 | 4445 | 2154 |
| `nbody` | 18 | 28 | 16 | 919 | 4433 | 2125 |
| `chacha20` | 48 | 40 | 16 | 923 | 4432 | 2125 |
| `poly1305` | 32 | 34 | 16 | 921 | 4432 | 2125 |
| `blake2b` | 32 | 42 | 16 | 925 | 4435 | 2127 |
| `sha512` | 32 | 41 | 16 | 922 | 4433 | 2126 |
| `x25519` | 44 | 47 | 48 | 1161 | 4465 | 2179 |

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
| _(floor: empty program)_ | _4_ | _320_ | _+7934 %_ | _12.146_ | _153.631_ | _+1165 %_ |
| `lcg` | 26 | 320 | +1120 % | 386.011 | 508.840 | +32 % |
| `packet_classifier` | 26 | 320 | +1123 % | 497.501 | 618.309 | +24 % |
| `ring_write` | 26 | 320 | +1120 % | 490.312 | 614.228 | +25 % |
| `histogram_bins` | 26 | 320 | +1118 % | 483.159 | 604.065 | +25 % |
| `prefix_scan` | 27 | 320 | +1104 % | 107.281 | 230.008 | +114 % |
| `binary_search` | 26 | 320 | +1115 % | 626.711 | 747.587 | +19 % |
| `sort_window` | 27 | 321 | +1106 % | 470.676 | 577.881 | +23 % |
| `bloom_filter` | 26 | 320 | +1111 % | 174.532 | 304.913 | +75 % |
| `hash_join` | 28 | 323 | +1040 % | 446.250 | 563.685 | +26 % |
| `sieve` | 26 | 320 | +1118 % | 460.153 | 589.383 | +28 % |
| `fib` | 26 | 320 | +1116 % | 385.903 | 517.302 | +34 % |
| `collatz` | 26 | 320 | +1124 % | 254.554 | 363.616 | +43 % |
| `matmul` | 27 | 320 | +1107 % | 176.465 | 299.808 | +70 % |
| `json_parse` | 46 | 335 | +624 % | 141.552 | 263.409 | +86 % |
| `nbody` | 28 | 322 | +1047 % | 415.005 | 543.852 | +31 % |
| `chacha20` | 40 | 401 | +894 % | 381.198 | 540.258 | +42 % |
| `poly1305` | 34 | 361 | +950 % | 996.987 | 1120.001 | +12 % |
| `blake2b` | 42 | 333 | +686 % | 592.899 | 720.787 | +22 % |
| `sha512` | 41 | 331 | +716 % | 587.205 | 714.663 | +22 % |
| `x25519` | 47 | 352 | +642 % | 2454.309 | 2601.135 | +6 % |

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
| _(floor: empty program)_ | _6.275_ | _118.811_ | _45.738_ | _55.062_ | _38.772_ | _60.898_ | _74.855_ |
| `lcg` | 6.062 | 130.207 | 47.088 | 62.202 | 37.501 | 66.599 | 83.165 |
| `packet_classifier` | 6.755 | 137.129 | 45.851 | 63.649 | 36.810 | 66.895 | 78.289 |
| `ring_write` | 15.157 | 148.437 | 56.924 | 65.907 | 36.757 | 69.063 | 79.713 |
| `histogram_bins` | 14.145 | 141.739 | 57.771 | 66.044 | 37.035 | 70.197 | 82.909 |
| `prefix_scan` | 15.411 | 153.126 | 59.024 | 70.926 | 38.911 | 75.146 | 85.839 |
| `binary_search` | 15.403 | 150.785 | 57.758 | 67.280 | 37.981 | 75.790 | 85.961 |
| `sort_window` | 15.419 | 158.551 | 58.917 | 71.133 | 37.676 | 79.511 | 91.525 |
| `bloom_filter` | 14.949 | 147.574 | 57.003 | 70.308 | 35.885 | 72.583 | 82.780 |
| `hash_join` | 18.403 | 249.690 | 67.848 | 106.359 | 38.130 | 108.730 | 119.861 |
| `sieve` | 14.915 | 149.463 | 57.049 | 73.128 | 36.618 | 82.073 | 90.835 |
| `fib` | 6.485 | 131.884 | 49.012 | 65.079 | 37.869 | 69.244 | 80.967 |
| `collatz` | 6.677 | 137.000 | 47.719 | 65.250 | 38.083 | 69.204 | 81.720 |
| `matmul` | 15.112 | 150.407 | 60.805 | 75.289 | 35.942 | 88.857 | 96.934 |
| `json_parse` | 44.733 | 424.648 | 125.276 | 113.235 | 39.224 | 181.712 | 161.239 |
| `nbody` | 16.678 | 160.113 | 65.060 | 89.625 | 37.191 | 91.032 | 101.189 |
| `chacha20` | 61.935 | 747.321 | 301.736 | 104.855 | 36.631 | 110.254 | 119.497 |
| `poly1305` | 54.670 | 481.112 | 121.010 | 97.424 | 38.193 | 119.541 | 130.533 |
| `blake2b` | 34.305 | 432.082 | 97.011 | 104.135 | 37.574 | 133.389 | 134.592 |
| `sha512` | 33.708 | 402.403 | 97.021 | 91.942 | 38.093 | 112.005 | 119.996 |
| `x25519` | 49.315 | 1506.045 | 132.685 | 724.638 | 39.771 | 633.036 | 650.670 |

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
