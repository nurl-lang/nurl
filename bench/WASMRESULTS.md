# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-04T18:05:59Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `255fdfe9083140904143f3dc86ec267c5ffdc03d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37222827546 |
| NURL | `v0.70.0-1-g255fdfe9` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.2), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 2.0.0 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
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
| _(floor: empty program)_ | _1.432_ | _11.077_ | _7.7_ | _1.532_ | _7.385_ | _4.8_ | _1.653_ | _32.645_ | _19.7_ |
| `lcg` | 39.070 | 65.780 | 1.7 | 39.140 | 65.697 | 1.7 | 39.145 | 72.390 | 1.8 |
| `packet_classifier` | 56.205 | 79.725 | 1.4 | 56.239 | 78.232 | 1.4 | 56.512 | 85.419 | 1.5 |
| `ring_write` | 42.074 | 81.236 | 1.9 | 42.208 | 77.716 | 1.8 | 42.360 | 83.602 | 2.0 |
| `histogram_bins` | 39.530 | 81.426 | 2.1 | 41.157 | 75.177 | 1.8 | 39.191 | 81.773 | 2.1 |
| `prefix_scan` | 21.713 | 36.948 | 1.7 | 21.734 | 37.918 | 1.7 | 21.944 | 44.161 | 2.0 |
| `binary_search` | 38.179 | 87.888 | 2.3 | 38.128 | 89.456 | 2.3 | 44.013 | 100.272 | 2.3 |
| `sort_window` | 27.221 | 70.797 | 2.6 | 27.177 | 60.591 | 2.2 | 26.675 | 67.011 | 2.5 |
| `bloom_filter` | 15.364 | 44.116 | 2.9 | 18.164 | 47.143 | 2.6 | 18.336 | 52.533 | 2.9 |
| `hash_join` | 27.925 | 72.228 | 2.6 | 30.087 | 81.506 | 2.7 | 29.822 | 78.756 | 2.6 |
| `sieve` | 18.039 | 71.355 | 4.0 | 17.849 | 59.270 | 3.3 | 18.062 | 58.327 | 3.2 |
| `fib` | 25.041 | 69.957 | 2.8 | 29.835 | 77.174 | 2.6 | 29.910 | 79.212 | 2.6 |
| `collatz` | 12.314 | 46.430 | 3.8 | 12.288 | 45.154 | 3.7 | 12.402 | 52.528 | 4.2 |
| `matmul` | 33.417 | 57.999 | 1.7 | 33.483 | 52.719 | 1.6 | 33.584 | 63.415 | 1.9 |
| `json_parse` | 9.590 | 54.765 | 5.7 | 8.635 | 39.389 | 4.6 | 11.708 | 62.110 | 5.3 |
| `nbody` | 40.736 | 75.507 | 1.9 | 40.746 | 75.281 | 1.8 | 38.935 | 76.016 | 2.0 |

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
| `lcg` | 1.5 | — | 1.6 | 1.1 |
| `packet_classifier` | 1.3 | — | 1.3 | 1.0 |
| `ring_write` | 1.7 | — | 1.7 | 1.3 |
| `histogram_bins` | 1.8 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.5 | — |
| `binary_search` | 2.1 | — | 2.2 | 1.6 |
| `sort_window` | 2.3 | — | 2.1 | 1.4 |
| `bloom_filter` | 2.4 | — | 2.4 | — |
| `hash_join` | 2.3 | — | 2.6 | 1.6 |
| `sieve` | 3.6 | — | 3.2 | — |
| `fib` | 2.5 | — | 2.5 | 1.6 |
| `collatz` | 3.2 | — | 3.5 | — |
| `matmul` | 1.5 | — | 1.4 | — |
| `json_parse` | 5.4 | — | 4.5 | — |
| `nbody` | 1.6 | — | 1.7 | 1.2 |

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

| Benchmark | NURL on `nwasm` | vs JIT | vs native | C on `nwasm` | Rust on `nwasm` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.445_ | _0.2_ | _1.7_ | _2.811_ | _3.639_ |
| `lcg` | 40.846 | 0.6 | 1.0 | 42.327 | 42.694 |
| `packet_classifier` | 60.697 | 0.8 | 1.1 | 61.743 | 63.928 |
| `ring_write` | 53.441 | 0.7 | 1.3 | 54.898 | 55.647 |
| `histogram_bins` | 55.319 | 0.7 | 1.4 | 60.942 | 57.840 |
| `prefix_scan` | 12.043 | 0.3 | 0.6 | 15.948 | 14.644 |
| `binary_search` | 66.144 | 0.8 | 1.7 | 68.904 | 101.366 |
| `sort_window` | 98.710 | 1.4 | 3.6 | 86.920 | 83.334 |
| `bloom_filter` | 22.414 | 0.5 | 1.5 | 26.058 | 24.557 |
| `hash_join` | 65.690 | 0.9 | 2.4 | 82.417 | 86.806 |
| `sieve` | 37.970 | 0.5 | 2.1 | 52.011 | 39.877 |
| `fib` | 73.838 | 1.1 | 2.9 | 72.364 | 73.778 |
| `collatz` | 25.740 | 0.6 | 2.1 | 27.217 | 27.585 |
| `matmul` | 29.441 | 0.5 | 0.9 | 36.346 | 36.659 |
| `json_parse` | 59.595 | 1.1 | 6.2 | 23.734 | 106.661 |
| `nbody` | 95.332 | 1.3 | 2.3 | 88.264 | 102.217 |

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
| `prefix_scan` | 17 | 26 | 16 | 916 | 4431 | 2129 |
| `binary_search` | 17 | 26 | 16 | 916 | 4432 | 2129 |
| `sort_window` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `bloom_filter` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `hash_join` | 25 | 28 | 16 | 923 | 4433 | 2131 |
| `sieve` | 17 | 26 | 16 | 916 | 4431 | 2128 |
| `fib` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `collatz` | 17 | 26 | 16 | 915 | 4430 | 2128 |
| `matmul` | 17 | 26 | 16 | 917 | 4431 | 2129 |
| `json_parse` | 40 | 47 | 16 | 1007 | 4445 | 2159 |
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
| _(floor: empty program)_ | _4_ | _305_ | _+7939 %_ | _11.077_ | _142.857_ | _+1190 %_ |
| `lcg` | 26 | 306 | +1077 % | 65.780 | 181.269 | +176 % |
| `packet_classifier` | 26 | 306 | +1080 % | 79.725 | 193.230 | +142 % |
| `ring_write` | 26 | 306 | +1077 % | 81.236 | 193.805 | +139 % |
| `histogram_bins` | 26 | 306 | +1075 % | 81.426 | 196.440 | +141 % |
| `prefix_scan` | 26 | 306 | +1062 % | 36.948 | 153.533 | +316 % |
| `binary_search` | 26 | 306 | +1072 % | 87.888 | 204.949 | +133 % |
| `sort_window` | 26 | 306 | +1063 % | 70.797 | 184.899 | +161 % |
| `bloom_filter` | 26 | 306 | +1068 % | 44.116 | 160.796 | +264 % |
| `hash_join` | 28 | 309 | +999 % | 72.228 | 187.476 | +160 % |
| `sieve` | 26 | 306 | +1077 % | 71.355 | 169.365 | +137 % |
| `fib` | 26 | 305 | +1081 % | 69.957 | 183.218 | +162 % |
| `collatz` | 26 | 306 | +1081 % | 46.430 | 162.339 | +250 % |
| `matmul` | 26 | 306 | +1066 % | 57.999 | 172.420 | +197 % |
| `json_parse` | 47 | 324 | +595 % | 54.765 | 173.422 | +217 % |
| `nbody` | 28 | 307 | +1006 % | 75.507 | 200.746 | +166 % |

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
| _(floor: empty program)_ | _3.375_ | _96.207_ | _52.157_ | _57.411_ | _41.066_ | _53.920_ | _66.511_ |
| `lcg` | 3.742 | 116.814 | 49.422 | 66.230 | 41.094 | 57.500 | 72.587 |
| `packet_classifier` | 3.683 | 114.558 | 49.320 | 66.194 | 41.175 | 57.199 | 71.664 |
| `ring_write` | 3.822 | 116.498 | 49.865 | 68.329 | 41.080 | 58.842 | 73.089 |
| `histogram_bins` | 4.010 | 119.779 | 52.063 | 70.189 | 40.724 | 60.716 | 74.341 |
| `prefix_scan` | 4.048 | 118.930 | 51.123 | 71.248 | 40.589 | 60.410 | 76.149 |
| `binary_search` | 4.290 | 119.364 | 51.990 | 68.759 | 41.216 | 62.840 | 77.473 |
| `sort_window` | 4.396 | 124.998 | 51.923 | 74.078 | 41.902 | 66.929 | 82.289 |
| `bloom_filter` | 4.874 | 124.707 | 52.591 | 75.245 | 41.454 | 64.524 | 77.604 |
| `hash_join` | 9.240 | 245.969 | 63.999 | 119.755 | 41.506 | 97.700 | 113.118 |
| `sieve` | 4.129 | 118.680 | 52.567 | 77.894 | 42.517 | 68.613 | 81.371 |
| `fib` | 3.635 | 113.116 | 50.197 | 66.033 | 40.694 | 56.716 | 70.849 |
| `collatz` | 3.907 | 115.607 | 50.572 | 66.208 | 40.406 | 58.310 | 72.956 |
| `matmul` | 4.729 | 123.283 | 53.397 | 80.216 | 40.806 | 77.733 | 90.460 |
| `json_parse` | 104.625 | 699.749 | 210.177 | 122.888 | 42.184 | 155.704 | 142.024 |
| `nbody` | 6.909 | 140.763 | 62.088 | 96.771 | 41.963 | 80.359 | 94.647 |

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
