# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-09T17:15:02Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
the next run overwrites it. The machine-readable form of this same run
is [`results/wasm-latest.json`](results/wasm-latest.json).

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
| Commit | `d1f4dfb423c11db5fd12ab33b9af67bd25fa7885` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37964381357 |
| NURL | `v0.71.0-13-gd1f4dfb4` |
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
| Workload scale | ×1 — the published contract (`--scale N` multiplies it) |
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
| _(floor: empty program)_ | _1.260_ | _10.600_ | _8.4_ | _1.347_ | _7.202_ | _5.3_ | _1.443_ | _28.624_ | _19.8_ |
| `lcg` | 37.896 | 62.122 | 1.6 | 38.890 | 63.850 | 1.6 | 36.074 | 64.039 | 1.8 |
| `packet_classifier` | 52.524 | 73.781 | 1.4 | 51.835 | 72.168 | 1.4 | 50.569 | 75.750 | 1.5 |
| `ring_write` | 39.538 | 69.945 | 1.8 | 39.165 | 70.565 | 1.8 | 39.019 | 75.388 | 1.9 |
| `histogram_bins` | 35.656 | 70.289 | 2.0 | 35.980 | 68.309 | 1.9 | 38.810 | 73.023 | 1.9 |
| `prefix_scan` | 19.668 | 32.135 | 1.6 | 20.451 | 35.355 | 1.7 | 20.871 | 35.234 | 1.7 |
| `binary_search` | 28.777 | 82.529 | 2.9 | 28.542 | 81.560 | 2.9 | 37.226 | 85.891 | 2.3 |
| `sort_window` | 25.148 | 64.419 | 2.6 | 24.203 | 55.030 | 2.3 | 23.971 | 56.479 | 2.4 |
| `bloom_filter` | 14.404 | 39.057 | 2.7 | 16.408 | 41.447 | 2.5 | 16.605 | 46.080 | 2.8 |
| `hash_join` | 23.750 | 60.567 | 2.6 | 26.029 | 67.516 | 2.6 | 28.669 | 69.891 | 2.4 |
| `sieve` | 16.019 | 47.258 | 3.0 | 16.013 | 52.886 | 3.3 | 16.456 | 48.301 | 2.9 |
| `fib` | 22.111 | 57.645 | 2.6 | 26.026 | 64.879 | 2.5 | 26.617 | 65.489 | 2.5 |
| `collatz` | 10.977 | 42.176 | 3.8 | 11.153 | 44.742 | 4.0 | 11.297 | 45.817 | 4.1 |
| `matmul` | 37.554 | 50.446 | 1.3 | 37.933 | 50.374 | 1.3 | 38.982 | 49.630 | 1.3 |
| `json_parse` | 7.610 | 47.900 | 6.3 | 7.081 | 33.318 | 4.7 | 9.364 | 51.464 | 5.5 |
| `nbody` | 38.627 | 67.343 | 1.7 | 39.502 | 59.308 | 1.5 | 35.557 | 68.245 | 1.9 |
| `chacha20` | 7.210 | 78.223 | 10.8 | 37.561 | 69.554 | 1.9 | 35.495 | 72.152 | 2.0 |
| `poly1305` | 21.459 | 127.005 | 5.9 | 19.873 | 120.003 | 6.0 | 20.616 | 145.340 | 7.0 |
| `blake2b` | 39.096 | 81.378 | 2.1 | 59.743 | 92.734 | 1.6 | 64.786 | 111.143 | 1.7 |
| `sha512` | 40.951 | 87.748 | 2.1 | 42.932 | 74.620 | 1.7 | 46.339 | 81.154 | 1.8 |
| `x25519` | 51.507 | 309.006 | 6.0 | 56.744 | 349.257 | 6.2 | 47.820 | 452.728 | 9.5 |

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
| `lcg` | 1.4 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 1.0 |
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.2 | — | 1.5 | — |
| `binary_search` | 2.6 | — | 2.7 | 1.6 |
| `sort_window` | 2.3 | — | 2.1 | — |
| `bloom_filter` | 2.2 | — | 2.3 | — |
| `hash_join` | 2.2 | — | 2.4 | 1.5 |
| `sieve` | 2.5 | — | 3.1 | — |
| `fib` | 2.3 | — | 2.3 | 1.5 |
| `collatz` | 3.2 | — | 3.8 | — |
| `matmul` | 1.1 | — | 1.2 | — |
| `json_parse` | 5.9 | — | 4.6 | — |
| `nbody` | 1.5 | — | 1.4 | 1.2 |
| `chacha20` | 11.4 | — | 1.7 | 1.3 |
| `poly1305` | 5.8 | — | 6.1 | 6.1 |
| `blake2b` | 1.9 | — | 1.5 | 1.3 |
| `sha512` | 1.9 | — | 1.6 | 1.2 |
| `x25519` | 5.9 | 5.1 | 6.2 | 9.1 |

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
| _(floor: empty program)_ | _10.600_ | _3.166_ | _7.202_ | _**2.675**_ | _28.624_ | _3.318_ |
| `lcg` | 62.122 | **39.766** | 63.850 | 43.473 | 64.039 | 42.666 |
| `packet_classifier` | 73.781 | **47.354** | 72.168 | 50.619 | 75.750 | 51.474 |
| `ring_write` | 69.945 | **44.302** | 70.565 | 48.039 | 75.388 | 47.875 |
| `histogram_bins` | 70.289 | **42.236** | 68.309 | 48.091 | 73.023 | 43.923 |
| `prefix_scan` | 32.135 | **11.043** | 35.355 | 15.966 | 35.234 | 13.592 |
| `binary_search` | 82.529 | **49.492** | 81.560 | 52.453 | 85.891 | 52.876 |
| `sort_window` | 64.419 | 43.672 | 55.030 | 40.336 | 56.479 | **38.940** |
| `bloom_filter` | 39.057 | **18.258** | 41.447 | 22.457 | 46.080 | 20.384 |
| `hash_join` | 60.567 | **37.235** | 67.516 | 39.812 | 69.891 | 39.469 |
| `sieve` | 47.258 | 28.041 | 52.886 | 34.280 | 48.301 | **27.606** |
| `fib` | 57.645 | 37.861 | 64.879 | 35.825 | 65.489 | **31.069** |
| `collatz` | 42.176 | **21.749** | 44.742 | 23.210 | 45.817 | 23.595 |
| `matmul` | 50.446 | 30.719 | 50.374 | 27.540 | 49.630 | **26.804** |
| `json_parse` | 47.900 | 26.340 | 33.318 | **17.809** | 51.464 | 23.941 |
| `nbody` | 67.343 | 47.755 | 59.308 | **44.220** | 68.245 | 46.306 |
| `chacha20` | 78.223 | 49.898 | 69.554 | 48.335 | 72.152 | **48.232** |
| `poly1305` | 127.005 | 66.264 | 120.003 | **54.311** | 145.340 | 56.945 |
| `blake2b` | 81.378 | **57.919** | 92.734 | 79.758 | 111.143 | 97.267 |
| `sha512` | 87.748 | **54.511** | 74.620 | 61.529 | 81.154 | 64.553 |
| `x25519` | 309.006 | **149.176** | 349.257 | 157.156 | 452.728 | 152.857 |

`nwasm` is faster than the reference runtime on 20 of 20 NURL modules,
20 of 20 C modules and 20 of 20 Rust modules.

The same cells as ratios: `vs JIT` is `nwasm` ÷ the reference runtime
for the same module, `vs native` is the NURL module on `nwasm` ÷ the
native NURL binary.

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C vs JIT | Rust vs JIT |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.166_ | _0.3_ | _2.5_ | _0.4_ | _0.1_ |
| `lcg` | 39.766 | 0.6 | 1.0 | 0.7 | 0.7 |
| `packet_classifier` | 47.354 | 0.6 | 0.9 | 0.7 | 0.7 |
| `ring_write` | 44.302 | 0.6 | 1.1 | 0.7 | 0.6 |
| `histogram_bins` | 42.236 | 0.6 | 1.2 | 0.7 | 0.6 |
| `prefix_scan` | 11.043 | 0.3 | 0.6 | 0.5 | 0.4 |
| `binary_search` | 49.492 | 0.6 | 1.7 | 0.6 | 0.6 |
| `sort_window` | 43.672 | 0.7 | 1.7 | 0.7 | 0.7 |
| `bloom_filter` | 18.258 | 0.5 | 1.3 | 0.5 | 0.4 |
| `hash_join` | 37.235 | 0.6 | 1.6 | 0.6 | 0.6 |
| `sieve` | 28.041 | 0.6 | 1.8 | 0.6 | 0.6 |
| `fib` | 37.861 | 0.7 | 1.7 | 0.6 | 0.5 |
| `collatz` | 21.749 | 0.5 | 2.0 | 0.5 | 0.5 |
| `matmul` | 30.719 | 0.6 | 0.8 | 0.5 | 0.5 |
| `json_parse` | 26.340 | 0.5 | 3.5 | 0.5 | 0.5 |
| `nbody` | 47.755 | 0.7 | 1.2 | 0.7 | 0.7 |
| `chacha20` | 49.898 | 0.6 | 6.9 | 0.7 | 0.7 |
| `poly1305` | 66.264 | 0.5 | 3.1 | 0.5 | 0.4 |
| `blake2b` | 57.919 | 0.7 | 1.5 | 0.9 | 0.9 |
| `sha512` | 54.511 | 0.6 | 1.3 | 0.8 | 0.8 |
| `x25519` | 149.176 | 0.5 | 2.9 | 0.4 | 0.3 |

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
| `hash_join` | 25 | 28 | 16 | 923 | 4433 | 2131 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `fib` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `collatz` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `matmul` | 17 | 26 | 16 | 917 | 4431 | 2129 |
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
| _(floor: empty program)_ | _4_ | _312_ | _+7737 %_ | _10.600_ | _130.916_ | _+1135 %_ |
| `lcg` | 26 | 312 | +1090 % | 62.122 | 159.413 | +157 % |
| `packet_classifier` | 26 | 312 | +1093 % | 73.781 | 167.596 | +127 % |
| `ring_write` | 26 | 312 | +1090 % | 69.945 | 170.981 | +144 % |
| `histogram_bins` | 26 | 312 | +1088 % | 70.289 | 172.278 | +145 % |
| `prefix_scan` | 27 | 312 | +1074 % | 32.135 | 132.190 | +311 % |
| `binary_search` | 26 | 312 | +1085 % | 82.529 | 170.966 | +107 % |
| `sort_window` | 27 | 313 | +1076 % | 64.419 | 171.658 | +166 % |
| `bloom_filter` | 26 | 312 | +1081 % | 39.057 | 141.351 | +262 % |
| `hash_join` | 28 | 315 | +1012 % | 60.567 | 156.240 | +158 % |
| `sieve` | 26 | 312 | +1090 % | 47.258 | 143.792 | +204 % |
| `fib` | 26 | 312 | +1094 % | 57.645 | 159.763 | +177 % |
| `collatz` | 26 | 312 | +1094 % | 42.176 | 139.100 | +230 % |
| `matmul` | 26 | 312 | +1079 % | 50.446 | 144.002 | +185 % |
| `json_parse` | 52 | 332 | +534 % | 47.900 | 147.346 | +208 % |
| `nbody` | 28 | 314 | +1019 % | 67.343 | 158.612 | +136 % |
| `chacha20` | 48 | 359 | +646 % | 78.223 | 176.298 | +125 % |
| `poly1305` | 35 | 316 | +813 % | 127.005 | 221.958 | +75 % |
| `blake2b` | 42 | 325 | +679 % | 81.378 | 176.687 | +117 % |
| `sha512` | 40 | 322 | +709 % | 87.748 | 179.260 | +104 % |
| `x25519` | 43 | 326 | +656 % | 309.006 | 389.583 | +26 % |

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
| _(floor: empty program)_ | _3.494_ | _97.757_ | _47.864_ | _65.621_ | _46.641_ | _60.400_ | _82.442_ |
| `lcg` | 3.887 | 119.066 | 52.362 | 68.082 | 40.786 | 69.984 | 77.275 |
| `packet_classifier` | 4.137 | 111.219 | 51.175 | 68.963 | 39.509 | 66.948 | 77.418 |
| `ring_write` | 3.887 | 115.618 | 48.847 | 66.112 | 42.491 | 70.656 | 82.624 |
| `histogram_bins` | 4.162 | 117.614 | 54.399 | 70.489 | 40.045 | 73.612 | 87.936 |
| `prefix_scan` | 4.381 | 124.106 | 54.056 | 71.626 | 39.139 | 69.167 | 81.676 |
| `binary_search` | 4.322 | 116.477 | 53.337 | 68.660 | 40.187 | 72.482 | 81.927 |
| `sort_window` | 4.374 | 122.825 | 52.782 | 73.804 | 39.376 | 75.065 | 82.792 |
| `bloom_filter` | 4.893 | 120.580 | 50.913 | 75.914 | 38.269 | 72.838 | 81.533 |
| `hash_join` | 8.809 | 221.033 | 66.671 | 102.877 | 38.086 | 104.510 | 109.376 |
| `sieve` | 4.205 | 117.779 | 52.972 | 71.474 | 42.500 | 75.111 | 88.852 |
| `fib` | 3.876 | 109.474 | 47.629 | 67.711 | 43.815 | 66.417 | 75.270 |
| `collatz` | 3.975 | 115.947 | 49.503 | 70.114 | 41.001 | 67.214 | 78.232 |
| `matmul` | 5.631 | 122.562 | 49.469 | 75.325 | 40.118 | 85.950 | 92.057 |
| `json_parse` | 42.617 | 600.627 | 128.663 | 116.757 | 39.874 | 165.990 | 132.860 |
| `nbody` | 6.885 | 131.812 | 56.666 | 86.629 | 37.171 | 84.084 | 95.365 |
| `chacha20` | 44.840 | 580.302 | 153.488 | 102.787 | 40.539 | 101.542 | 112.933 |
| `poly1305` | 28.674 | 285.670 | 87.956 | 103.652 | 38.662 | 106.992 | 117.622 |
| `blake2b` | 31.158 | 406.054 | 101.050 | 99.645 | 43.181 | 114.950 | 124.035 |
| `sha512` | 33.264 | 405.206 | 113.794 | 88.704 | 42.528 | 101.238 | 112.459 |
| `x25519` | 36.518 | 429.277 | 121.850 | 628.000 | 39.735 | 529.313 | 559.442 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `chacha20` | `3720502699256473595` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `poly1305` | `2498856793803813402` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `blake2b` | `8590291023788228918` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `sha512` | `7091519178481951668` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |
| `x25519` | `6127485567278337128` | identical: 3 languages x {native, JIT, interpreter}, + NURL wasm `--no-gc-sections` |

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
