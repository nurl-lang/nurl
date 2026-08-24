# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-24T18:09:35Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Memory | 16377684 KiB |
| Commit | `065129f57fd5329d2aa4e3c41976edccafc5ed3c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32760502135 |
| NURL | `v0.50.0-24-g065129f5` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.0), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.0 (f1412a598 2026-08-20)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/wasmtime` (wasmtime 0.15.0 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `-O2`, Rust `-C opt-level=2`, both targets |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 900 s |
| C/Rust on the NURL interpreter | no (add --wt-all-langs) |
| Reference runtime cache | **off** (`-C cache=n`) — every cell is decode + compile + run |
| `wt` build | `NURL_SPLIT=0` — `nurl.sh` otherwise lowers a large program as one module per core, and ThinLTO cannot import every callee back across a part boundary. `wt` is the subject of section 3, and the reference runtime it is measured against is a release build; a split `wt` measured 5.0% slower over this corpus. |

## 1. What wasm costs — native vs the same module on a JIT

Whole-process wall clock in milliseconds, start-up included. The `x`
columns are wasm ÷ native for that language: how much slower the *same
source* got by being compiled to wasm and run under a JIT instead of
straight to the machine. Because all three languages appear, the column
answers a question a NURL-only table could not: whether a gap belongs to
NURL's wasm pipeline or to wasm itself.

| Benchmark | NURL native | NURL wasm | x | C native | C wasm | x | Rust native | Rust wasm | x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.472_ | _11.591_ | _7.9_ | _1.561_ | _6.616_ | _4.2_ | _1.700_ | _33.090_ | _19.5_ |
| `lcg` | 39.224 | 67.484 | 1.7 | 39.299 | 65.450 | 1.7 | 39.448 | 74.775 | 1.9 |
| `packet_classifier` | 56.274 | 80.700 | 1.4 | 56.414 | 78.750 | 1.4 | 56.574 | 87.963 | 1.6 |
| `ring_write` | 42.214 | 79.306 | 1.9 | 42.313 | 78.405 | 1.9 | 42.539 | 85.759 | 2.0 |
| `histogram_bins` | 39.592 | 78.243 | 2.0 | 41.273 | 74.008 | 1.8 | 41.465 | 83.608 | 2.0 |
| `prefix_scan` | 21.883 | 39.098 | 1.8 | 22.027 | 38.449 | 1.7 | 21.993 | 47.276 | 2.1 |
| `binary_search` | 39.973 | 92.331 | 2.3 | 38.529 | 89.700 | 2.3 | 38.256 | 99.775 | 2.6 |
| `sort_window` | 27.418 | 72.093 | 2.6 | 27.513 | 58.752 | 2.1 | 27.008 | 67.997 | 2.5 |
| `bloom_filter` | 17.688 | 45.178 | 2.6 | 18.369 | 45.617 | 2.5 | 18.569 | 53.469 | 2.9 |
| `hash_join` | 28.040 | 70.003 | 2.5 | 30.241 | 71.971 | 2.4 | 30.019 | 84.229 | 2.8 |
| `sieve` | 18.596 | 55.425 | 3.0 | 18.526 | 57.111 | 3.1 | 18.414 | 59.991 | 3.3 |
| `fib` | 25.264 | 72.650 | 2.9 | 30.011 | 70.891 | 2.4 | 25.501 | 80.519 | 3.2 |
| `collatz` | 12.307 | 47.421 | 3.9 | 12.341 | 46.304 | 3.8 | 12.445 | 54.641 | 4.4 |
| `matmul` | 33.761 | 56.721 | 1.7 | 33.670 | 50.283 | 1.5 | 33.808 | 63.127 | 1.9 |
| `json_parse` | 8.947 | 50.951 | 5.7 | 8.763 | 40.559 | 4.6 | 11.837 | 58.592 | 4.9 |
| `nbody` | 40.853 | 80.317 | 2.0 | 40.826 | 67.911 | 1.7 | 38.994 | 76.370 | 2.0 |

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
| `ring_write` | 1.7 | — | 1.8 | 1.3 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.3 |
| `prefix_scan` | 1.3 | — | 1.6 | — |
| `binary_search` | 2.1 | — | 2.2 | 1.8 |
| `sort_window` | 2.3 | — | 2.0 | 1.4 |
| `bloom_filter` | 2.1 | — | 2.3 | — |
| `hash_join` | 2.2 | — | 2.3 | 1.8 |
| `sieve` | 2.6 | — | 3.0 | — |
| `fib` | 2.6 | — | 2.3 | 2.0 |
| `collatz` | 3.3 | — | 3.7 | — |
| `matmul` | 1.4 | — | 1.4 | — |
| `json_parse` | 5.3 | — | 4.7 | — |
| `nbody` | 1.7 | — | 1.6 | 1.2 |

## 3. The pure-NURL runtime (`packages/wasmtime`)

The identical modules from section 1, executed by a runtime written in
NURL instead of in Rust: a register-record interpreter with a template
JIT on top (on by default; `NURL_WT_JIT=0` keeps the pure interpreter,
and metered or shared-memory runs fall back to it on their own).
`vs JIT` is the cost of the runtime; `vs native` is the end-to-end
cost of choosing this way to ship. The size of the gap is measured
rather than assumed, per benchmark, so it can be aimed at.

Read the floor row first, because it goes the other way: on a program
that does nothing this runtime *beats* the reference. Nothing surprising
is happening — the reference compiles the whole module before `_start`,
and `wt` only decodes it, compiling nothing but what runs. That
crossover is the honest answer to "which runtime should I use": it
depends entirely on how long the guest runs.

| Benchmark | NURL on `wt` | vs JIT | vs native | C on `wt` | Rust on `wt` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.359_ | _0.3_ | _2.3_ | _SKIPPED_ | _SKIPPED_ |
| `lcg` | 41.854 | 0.6 | 1.1 | SKIPPED | SKIPPED |
| `packet_classifier` | 57.587 | 0.7 | 1.0 | SKIPPED | SKIPPED |
| `ring_write` | 56.803 | 0.7 | 1.3 | SKIPPED | SKIPPED |
| `histogram_bins` | 49.693 | 0.6 | 1.3 | SKIPPED | SKIPPED |
| `prefix_scan` | 15.872 | 0.4 | 0.7 | SKIPPED | SKIPPED |
| `binary_search` | 99.385 | 1.1 | 2.5 | SKIPPED | SKIPPED |
| `sort_window` | 103.431 | 1.4 | 3.8 | SKIPPED | SKIPPED |
| `bloom_filter` | 26.745 | 0.6 | 1.5 | SKIPPED | SKIPPED |
| `hash_join` | 88.251 | 1.3 | 3.1 | SKIPPED | SKIPPED |
| `sieve` | 48.798 | 0.9 | 2.6 | SKIPPED | SKIPPED |
| `fib` | 103.420 | 1.4 | 4.1 | SKIPPED | SKIPPED |
| `collatz` | 28.393 | 0.6 | 2.3 | SKIPPED | SKIPPED |
| `matmul` | 33.936 | 0.6 | 1.0 | SKIPPED | SKIPPED |
| `json_parse` | 68.457 | 1.3 | 7.7 | SKIPPED | SKIPPED |
| `nbody` | 127.695 | 1.6 | 3.1 | SKIPPED | SKIPPED |

The C and Rust columns are `SKIPPED`: they are the cross-frontend
control — modules this runtime never saw during development, from two
other LLVM frontends — and running them costs about three times the
whole rest of the suite, so they are opt-in. `--wt-all-langs` fills
them in. Until it is run, this section says what the interpreter does
with NURL output and nothing about whether it is tuned for it.

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
| `binary_search` | 16 | 1093 | 16 | 916 | 4404 | 2084 |
| `sort_window` | 16 | 1094 | 16 | 917 | 4404 | 2084 |
| `bloom_filter` | 16 | 1093 | 16 | 917 | 4403 | 2084 |
| `hash_join` | 20 | 1095 | 16 | 923 | 4406 | 2086 |
| `sieve` | 16 | 1093 | 16 | 916 | 4403 | 2084 |
| `fib` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `collatz` | 16 | 1093 | 16 | 915 | 4402 | 2083 |
| `matmul` | 16 | 1093 | 16 | 917 | 4403 | 2084 |
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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _11.591_ | _144.720_ | _+1149 %_ |
| `lcg` | 1093 | 1394 | +28 % | 67.484 | 177.148 | +163 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 80.700 | 190.974 | +137 % |
| `ring_write` | 1093 | 1394 | +28 % | 79.306 | 189.216 | +139 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 78.243 | 187.355 | +139 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 39.098 | 151.129 | +287 % |
| `binary_search` | 1093 | 1394 | +28 % | 92.331 | 199.163 | +116 % |
| `sort_window` | 1094 | 1395 | +28 % | 72.093 | 184.023 | +155 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 45.178 | 156.379 | +246 % |
| `hash_join` | 1095 | 1397 | +28 % | 70.003 | 177.134 | +153 % |
| `sieve` | 1093 | 1394 | +28 % | 55.425 | 170.943 | +208 % |
| `fib` | 1093 | 1394 | +28 % | 72.650 | 181.080 | +149 % |
| `collatz` | 1093 | 1394 | +28 % | 47.421 | 155.223 | +227 % |
| `matmul` | 1093 | 1394 | +28 % | 56.721 | 168.439 | +197 % |
| `json_parse` | 1119 | 1417 | +27 % | 50.951 | 169.159 | +232 % |
| `nbody` | 1095 | 1396 | +27 % | 80.317 | 184.788 | +130 % |

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
| _(floor: empty program)_ | _2.684_ | _96.355_ | _61.133_ | _59.799_ | _42.305_ | _56.041_ | _69.906_ |
| `lcg` | 2.947 | 105.024 | 60.767 | 68.799 | 42.695 | 61.812 | 76.338 |
| `packet_classifier` | 2.900 | 104.811 | 63.954 | 68.962 | 41.748 | 60.752 | 75.254 |
| `ring_write` | 2.989 | 104.350 | 59.986 | 69.063 | 41.818 | 61.441 | 76.142 |
| `histogram_bins` | 3.033 | 106.713 | 59.960 | 72.174 | 41.758 | 63.310 | 77.788 |
| `prefix_scan` | 3.194 | 111.702 | 61.949 | 75.053 | 42.990 | 65.838 | 80.115 |
| `binary_search` | 3.323 | 110.234 | 67.370 | 71.674 | 42.606 | 68.683 | 81.205 |
| `sort_window` | 3.459 | 118.192 | 63.266 | 78.415 | 44.006 | 72.223 | 86.676 |
| `bloom_filter` | 3.627 | 116.314 | 63.577 | 78.748 | 43.206 | 68.621 | 83.179 |
| `hash_join` | 6.243 | 234.577 | 76.486 | 122.982 | 42.833 | 104.863 | 118.477 |
| `sieve` | 3.186 | 111.176 | 62.075 | 82.680 | 43.372 | 73.257 | 84.662 |
| `fib` | 2.844 | 100.771 | 59.659 | 67.663 | 41.573 | 59.354 | 72.846 |
| `collatz` | 3.018 | 106.313 | 60.620 | 69.159 | 42.049 | 61.727 | 76.658 |
| `matmul` | 3.361 | 112.527 | 61.583 | 81.855 | 42.133 | 86.268 | 94.040 |
| `json_parse` | 53.112 | 616.400 | 149.155 | 127.614 | 43.151 | 173.738 | 150.813 |
| `nbody` | 4.731 | 124.760 | 69.749 | 98.104 | 41.662 | 85.560 | 97.928 |

## 7. Correctness gate

Each row is timed only when all ten cells print the same line as the
native NURL binary. The interpreter is inside the gate, not beside it:
a runtime that gets the wrong answer quickly is not a fast runtime.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `packet_classifier` | `4205972061` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `ring_write` | `8299504528805184357` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `histogram_bins` | `1215643728` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `prefix_scan` | `492982549` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `binary_search` | `805907445` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sort_window` | `2815490238` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `bloom_filter` | `2351703` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `hash_join` | `6152419568754618368` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `sieve` | `664579` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `fib` | `9227465` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `collatz` | `350` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `matmul` | `393199` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `json_parse` | `20` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |
| `nbody` | `4595260366167553674` | identical: 3 languages x {native, JIT, interpreter (NURL only)}, + NURL wasm `--no-gc-sections` |

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
