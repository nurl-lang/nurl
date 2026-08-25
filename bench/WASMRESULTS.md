# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-25T03:57:14Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372432 KiB |
| Commit | `3bd88f9cd1bd35d2d474902fa9be2796f5528baa` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32806901915 |
| NURL | `v0.51.0-15-g3bd88f9c` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.8 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.297_ | _9.526_ | _7.3_ | _1.336_ | _6.547_ | _4.9_ | _1.468_ | _36.815_ | _25.1_ |
| `lcg` | 41.806 | 68.018 | 1.6 | 42.142 | 66.148 | 1.6 | 42.029 | 75.892 | 1.8 |
| `packet_classifier` | 65.579 | 77.429 | 1.2 | 72.545 | 76.623 | 1.1 | 70.954 | 89.039 | 1.3 |
| `ring_write` | 45.583 | 81.666 | 1.8 | 46.123 | 79.663 | 1.7 | 45.988 | 89.464 | 1.9 |
| `histogram_bins` | 42.205 | 76.607 | 1.8 | 42.573 | 74.162 | 1.7 | 42.537 | 83.437 | 2.0 |
| `prefix_scan` | 22.590 | 36.676 | 1.6 | 23.200 | 35.393 | 1.5 | 23.812 | 44.188 | 1.9 |
| `binary_search` | 35.068 | 85.490 | 2.4 | 32.444 | 86.289 | 2.7 | 33.751 | 103.176 | 3.1 |
| `sort_window` | 42.537 | 71.690 | 1.7 | 53.222 | 63.043 | 1.2 | 41.976 | 71.369 | 1.7 |
| `bloom_filter` | 14.834 | 42.016 | 2.8 | 14.896 | 39.898 | 2.7 | 15.079 | 52.195 | 3.5 |
| `hash_join` | 25.146 | 63.890 | 2.5 | 27.606 | 73.907 | 2.7 | 28.070 | 79.371 | 2.8 |
| `sieve` | 37.933 | 71.126 | 1.9 | 37.354 | 78.250 | 2.1 | 37.313 | 75.800 | 2.0 |
| `fib` | 29.711 | 71.096 | 2.4 | 30.864 | 60.841 | 2.0 | 29.589 | 74.496 | 2.5 |
| `collatz` | 15.542 | 47.032 | 3.0 | 16.009 | 45.710 | 2.9 | 16.535 | 53.917 | 3.3 |
| `matmul` | 21.094 | 48.687 | 2.3 | 21.184 | 44.895 | 2.1 | 21.385 | 56.040 | 2.6 |
| `json_parse` | 8.136 | 46.087 | 5.7 | 7.964 | 40.968 | 5.1 | 9.827 | 55.229 | 5.6 |
| `nbody` | 33.826 | 63.061 | 1.9 | 33.848 | 59.477 | 1.8 | 30.928 | 72.631 | 2.3 |

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
| `packet_classifier` | 1.1 | — | 1.0 | 0.8 |
| `ring_write` | 1.6 | — | 1.6 | 1.2 |
| `histogram_bins` | 1.6 | — | 1.6 | 1.1 |
| `prefix_scan` | 1.3 | — | 1.3 | — |
| `binary_search` | 2.2 | — | 2.6 | 2.1 |
| `sort_window` | 1.5 | — | 1.1 | — |
| `bloom_filter` | 2.4 | — | 2.5 | — |
| `hash_join` | 2.3 | — | 2.6 | 1.6 |
| `sieve` | 1.7 | — | 2.0 | 1.1 |
| `fib` | 2.2 | — | 1.8 | 1.3 |
| `collatz` | 2.6 | — | 2.7 | — |
| `matmul` | 2.0 | — | 1.9 | — |
| `json_parse` | 5.3 | — | 5.2 | — |
| `nbody` | 1.6 | — | 1.6 | — |

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
| _(floor: empty program)_ | _2.584_ | _0.3_ | _2.0_ | _2.326_ | _2.822_ |
| `lcg` | 44.469 | 0.7 | 1.1 | 44.146 | 44.740 |
| `packet_classifier` | 62.396 | 0.8 | 1.0 | 62.027 | 64.554 |
| `ring_write` | 57.551 | 0.7 | 1.3 | 59.197 | 61.291 |
| `histogram_bins` | 58.523 | 0.8 | 1.4 | 60.849 | 60.323 |
| `prefix_scan` | 12.299 | 0.3 | 0.5 | 14.934 | 18.298 |
| `binary_search` | 62.087 | 0.7 | 1.8 | 59.059 | 96.539 |
| `sort_window` | 104.478 | 1.5 | 2.5 | 51.958 | 57.158 |
| `bloom_filter` | 31.559 | 0.8 | 2.1 | 28.327 | 26.635 |
| `hash_join` | 63.877 | 1.0 | 2.5 | 63.599 | 66.391 |
| `sieve` | 63.557 | 0.9 | 1.7 | 58.740 | 54.737 |
| `fib` | 77.769 | 1.1 | 2.6 | 66.748 | 61.345 |
| `collatz` | 33.503 | 0.7 | 2.2 | 33.525 | 33.359 |
| `matmul` | 25.159 | 0.5 | 1.2 | 28.986 | 27.853 |
| `json_parse` | 37.581 | 0.8 | 4.6 | 17.888 | 90.966 |
| `nbody` | 74.863 | 1.2 | 2.2 | 61.690 | 68.748 |

The C and Rust columns are the control. They are modules this runtime
never saw during development, emitted by two other LLVM frontends; that
they run at all is a correctness result, and that they run at a similar
ratio says the interpreter has no NURL-shaped fast path.

## 4. Artefact size (KiB)

A wasm module carries its own copy of everything it links — wasi-libc,
the language runtime — where a native binary borrows the system one.
These are the bytes that have to be shipped, and (for the two runtimes
above) parsed before the program starts.

| Benchmark | NURL native | NURL wasm | C native | C wasm | Rust native | Rust wasm |
|---|---:|---:|---:|---:|---:|---:|
| `lcg` | 16 | 1093 | 16 | 915 | 4403 | 2084 |
| `packet_classifier` | 16 | 1093 | 16 | 915 | 4403 | 2084 |
| `ring_write` | 16 | 1093 | 16 | 915 | 4403 | 2084 |
| `histogram_bins` | 16 | 1093 | 16 | 916 | 4404 | 2084 |
| `prefix_scan` | 16 | 1094 | 16 | 916 | 4403 | 2084 |
| `binary_search` | 16 | 1094 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1094 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1094 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1096 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1093 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1094 | 16 | 917 | 4403 | 2084 |
| `json_parse` | 35 | 1119 | 16 | 1007 | 4417 | 2111 |
| `nbody` | 16 | 1095 | 16 | 919 | 4404 | 2085 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _9.526_ | _137.679_ | _+1345 %_ |
| `lcg` | 1093 | 1395 | +28 % | 68.018 | 172.692 | +154 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 77.429 | 187.422 | +142 % |
| `ring_write` | 1093 | 1395 | +28 % | 81.666 | 185.611 | +127 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 76.607 | 180.839 | +136 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 36.676 | 146.852 | +300 % |
| `binary_search` | 1094 | 1395 | +28 % | 85.490 | 194.360 | +127 % |
| `sort_window` | 1094 | 1395 | +28 % | 71.690 | 183.338 | +156 % |
| `bloom_filter` | 1094 | 1395 | +28 % | 42.016 | 147.631 | +251 % |
| `hash_join` | 1096 | 1398 | +28 % | 63.890 | 173.266 | +171 % |
| `sieve` | 1093 | 1395 | +28 % | 71.126 | 184.751 | +160 % |
| `fib` | 1093 | 1394 | +28 % | 71.096 | 183.505 | +158 % |
| `collatz` | 1093 | 1395 | +28 % | 47.032 | 154.754 | +229 % |
| `matmul` | 1094 | 1395 | +28 % | 48.687 | 154.598 | +218 % |
| `json_parse` | 1119 | 1418 | +27 % | 46.087 | 155.590 | +238 % |
| `nbody` | 1095 | 1396 | +27 % | 63.061 | 175.805 | +179 % |

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
| _(floor: empty program)_ | _2.516_ | _85.681_ | _50.102_ | _54.398_ | _34.751_ | _54.855_ | _67.482_ |
| `lcg` | 2.769 | 96.294 | 54.157 | 60.646 | 97.766 | 62.623 | 105.429 |
| `packet_classifier` | 2.849 | 95.181 | 50.244 | 62.471 | 35.838 | 60.884 | 73.395 |
| `ring_write` | 2.953 | 95.314 | 50.108 | 62.485 | 35.248 | 62.400 | 75.508 |
| `histogram_bins` | 2.984 | 99.769 | 50.512 | 64.289 | 36.014 | 63.732 | 76.166 |
| `prefix_scan` | 3.014 | 99.761 | 50.651 | 65.611 | 35.647 | 63.808 | 76.285 |
| `binary_search` | 3.184 | 98.277 | 52.416 | 63.059 | 34.170 | 66.668 | 79.786 |
| `sort_window` | 3.281 | 105.171 | 52.182 | 69.865 | 35.624 | 71.714 | 85.130 |
| `bloom_filter` | 3.488 | 103.598 | 52.376 | 69.836 | 35.467 | 67.690 | 80.401 |
| `hash_join` | 5.943 | 205.930 | 60.440 | 107.817 | 35.129 | 104.530 | 123.628 |
| `sieve` | 3.036 | 99.518 | 51.420 | 69.622 | 34.769 | 71.797 | 83.875 |
| `fib` | 2.849 | 92.658 | 49.375 | 61.756 | 35.053 | 60.234 | 72.039 |
| `collatz` | 2.946 | 97.140 | 51.224 | 62.788 | 36.174 | 64.035 | 77.089 |
| `matmul` | 3.203 | 103.662 | 51.951 | 73.300 | 36.113 | 86.493 | 94.481 |
| `json_parse` | 51.754 | 550.982 | 131.232 | 111.924 | 37.185 | 179.699 | 157.340 |
| `nbody` | 4.470 | 117.390 | 58.833 | 87.763 | 35.940 | 88.969 | 99.003 |

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
