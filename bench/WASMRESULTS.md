# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-06T04:10:25Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `0ae00340604700fba67fd8e9fd5309e85da8fa82` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37412137220 |
| NURL | `v0.70.0-12-g0ae00340` |
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
| _(floor: empty program)_ | _1.412_ | _11.576_ | _8.2_ | _1.475_ | _6.032_ | _4.1_ | _1.626_ | _33.607_ | _20.7_ |
| `lcg` | 38.979 | 65.139 | 1.7 | 39.068 | 65.804 | 1.7 | 39.188 | 72.816 | 1.9 |
| `packet_classifier` | 56.089 | 77.864 | 1.4 | 56.260 | 79.122 | 1.4 | 56.255 | 84.503 | 1.5 |
| `ring_write` | 42.176 | 77.784 | 1.8 | 42.238 | 77.282 | 1.8 | 42.296 | 83.762 | 2.0 |
| `histogram_bins` | 38.924 | 80.452 | 2.1 | 41.155 | 75.573 | 1.8 | 39.130 | 81.282 | 2.1 |
| `prefix_scan` | 21.506 | 35.797 | 1.7 | 21.677 | 37.261 | 1.7 | 21.834 | 45.891 | 2.1 |
| `binary_search` | 39.005 | 89.441 | 2.3 | 38.144 | 88.525 | 2.3 | 44.183 | 95.193 | 2.2 |
| `sort_window` | 27.123 | 70.178 | 2.6 | 27.183 | 56.966 | 2.1 | 26.683 | 65.076 | 2.4 |
| `bloom_filter` | 15.720 | 44.191 | 2.8 | 17.977 | 45.011 | 2.5 | 18.303 | 55.252 | 3.0 |
| `hash_join` | 28.602 | 68.981 | 2.4 | 29.946 | 71.589 | 2.4 | 29.714 | 90.332 | 3.0 |
| `sieve` | 18.026 | 61.761 | 3.4 | 17.586 | 58.902 | 3.3 | 17.682 | 56.049 | 3.2 |
| `fib` | 29.667 | 70.019 | 2.4 | 29.967 | 73.193 | 2.4 | 29.878 | 78.705 | 2.6 |
| `collatz` | 12.202 | 44.743 | 3.7 | 12.249 | 45.257 | 3.7 | 12.383 | 51.141 | 4.1 |
| `matmul` | 33.334 | 57.191 | 1.7 | 33.311 | 49.863 | 1.5 | 33.414 | 60.982 | 1.8 |
| `json_parse` | 9.569 | 59.114 | 6.2 | 8.636 | 40.915 | 4.7 | 11.619 | 57.561 | 5.0 |
| `nbody` | 40.564 | 80.154 | 2.0 | 40.618 | 67.156 | 1.7 | 38.853 | 76.226 | 2.0 |

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
| `lcg` | 1.4 | — | 1.6 | 1.0 |
| `packet_classifier` | 1.2 | — | 1.3 | 0.9 |
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.8 | — | 1.8 | 1.3 |
| `prefix_scan` | 1.2 | — | 1.5 | — |
| `binary_search` | 2.1 | — | 2.2 | 1.4 |
| `sort_window` | 2.3 | — | 2.0 | — |
| `bloom_filter` | 2.3 | — | 2.4 | — |
| `hash_join` | 2.1 | — | 2.3 | 2.0 |
| `sieve` | 3.0 | — | 3.3 | — |
| `fib` | 2.1 | — | 2.4 | 1.6 |
| `collatz` | 3.1 | — | 3.6 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.8 | — | 4.9 | — |
| `nbody` | 1.8 | — | 1.6 | 1.1 |

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
| _(floor: empty program)_ | _2.610_ | _0.2_ | _1.8_ | _2.665_ | _3.615_ |
| `lcg` | 40.878 | 0.6 | 1.0 | 42.391 | 42.604 |
| `packet_classifier` | 60.747 | 0.8 | 1.1 | 61.864 | 63.577 |
| `ring_write` | 53.576 | 0.7 | 1.3 | 54.637 | 55.350 |
| `histogram_bins` | 58.381 | 0.7 | 1.5 | 58.775 | 57.528 |
| `prefix_scan` | 12.378 | 0.3 | 0.6 | 15.345 | 14.436 |
| `binary_search` | 66.153 | 0.7 | 1.7 | 69.006 | 101.472 |
| `sort_window` | 98.689 | 1.4 | 3.6 | 86.863 | 81.495 |
| `bloom_filter` | 23.053 | 0.5 | 1.5 | 26.339 | 24.767 |
| `hash_join` | 70.879 | 1.0 | 2.5 | 82.224 | 86.809 |
| `sieve` | 39.913 | 0.6 | 2.2 | 42.341 | 40.601 |
| `fib` | 73.083 | 1.0 | 2.5 | 71.810 | 76.115 |
| `collatz` | 25.955 | 0.6 | 2.1 | 26.934 | 28.320 |
| `matmul` | 32.036 | 0.6 | 1.0 | 35.600 | 39.808 |
| `json_parse` | 59.850 | 1.0 | 6.3 | 23.832 | 106.444 |
| `nbody` | 95.450 | 1.2 | 2.4 | 92.368 | 101.770 |

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
| `json_parse` | 41 | 49 | 16 | 1007 | 4445 | 2159 |
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
| _(floor: empty program)_ | _4_ | _311_ | _+7720 %_ | _11.576_ | _150.171_ | _+1197 %_ |
| `lcg` | 26 | 311 | +1091 % | 65.139 | 184.915 | +184 % |
| `packet_classifier` | 26 | 311 | +1094 % | 77.864 | 195.129 | +151 % |
| `ring_write` | 26 | 311 | +1091 % | 77.784 | 194.569 | +150 % |
| `histogram_bins` | 26 | 312 | +1088 % | 80.452 | 199.765 | +148 % |
| `prefix_scan` | 27 | 312 | +1075 % | 35.797 | 159.374 | +345 % |
| `binary_search` | 26 | 311 | +1086 % | 89.441 | 202.698 | +127 % |
| `sort_window` | 27 | 312 | +1077 % | 70.178 | 185.249 | +164 % |
| `bloom_filter` | 26 | 312 | +1082 % | 44.191 | 164.180 | +272 % |
| `hash_join` | 28 | 314 | +1013 % | 68.981 | 185.751 | +169 % |
| `sieve` | 26 | 311 | +1091 % | 61.761 | 172.873 | +180 % |
| `fib` | 26 | 311 | +1094 % | 70.019 | 194.247 | +177 % |
| `collatz` | 26 | 311 | +1095 % | 44.743 | 163.856 | +266 % |
| `matmul` | 26 | 311 | +1080 % | 57.191 | 173.627 | +204 % |
| `json_parse` | 49 | 330 | +569 % | 59.114 | 170.591 | +189 % |
| `nbody` | 28 | 313 | +1019 % | 80.154 | 192.976 | +141 % |

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
| _(floor: empty program)_ | _3.374_ | _95.808_ | _48.083_ | _55.198_ | _40.271_ | _51.800_ | _65.532_ |
| `lcg` | 3.591 | 113.920 | 48.721 | 64.629 | 40.146 | 56.628 | 71.239 |
| `packet_classifier` | 3.742 | 114.225 | 48.553 | 65.438 | 39.815 | 56.420 | 71.516 |
| `ring_write` | 3.952 | 115.386 | 49.378 | 66.492 | 39.592 | 57.571 | 72.122 |
| `histogram_bins` | 4.052 | 118.643 | 50.331 | 67.231 | 40.123 | 59.709 | 74.130 |
| `prefix_scan` | 4.088 | 119.696 | 50.106 | 69.953 | 40.248 | 59.720 | 75.044 |
| `binary_search` | 4.271 | 117.593 | 50.977 | 66.797 | 44.823 | 61.960 | 76.391 |
| `sort_window` | 4.563 | 125.520 | 50.995 | 73.590 | 39.892 | 66.613 | 80.505 |
| `bloom_filter` | 5.037 | 125.280 | 52.565 | 74.711 | 41.144 | 63.358 | 77.162 |
| `hash_join` | 9.174 | 243.079 | 63.239 | 117.466 | 40.168 | 96.904 | 111.349 |
| `sieve` | 4.106 | 119.035 | 49.982 | 75.938 | 40.198 | 66.435 | 79.501 |
| `fib` | 3.709 | 111.892 | 48.548 | 64.219 | 40.773 | 55.743 | 69.957 |
| `collatz` | 3.983 | 116.540 | 49.690 | 65.575 | 40.304 | 57.902 | 72.114 |
| `matmul` | 4.624 | 123.071 | 51.605 | 78.594 | 40.026 | 75.937 | 88.612 |
| `json_parse` | 48.285 | 630.591 | 146.674 | 120.789 | 40.559 | 153.618 | 140.139 |
| `nbody` | 6.827 | 137.557 | 61.111 | 94.330 | 40.003 | 79.269 | 92.221 |

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
