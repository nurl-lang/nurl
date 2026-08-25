# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-08-25T00:06:01Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| Commit | `164eef8601752a787bc00001060191dfcfd760ed` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32792020208 |
| NURL | `v0.51.0-5-g164eef86` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.2.1), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.1 (7bac2c277 2026-08-24)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.4 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.211_ | _9.105_ | _7.5_ | _1.282_ | _5.817_ | _4.5_ | _1.388_ | _29.332_ | _21.1_ |
| `lcg` | 34.223 | 56.980 | 1.7 | 34.169 | 55.800 | 1.6 | 34.310 | 61.164 | 1.8 |
| `packet_classifier` | 49.218 | 69.602 | 1.4 | 49.322 | 68.894 | 1.4 | 49.431 | 72.876 | 1.5 |
| `ring_write` | 36.924 | 67.618 | 1.8 | 36.986 | 66.905 | 1.8 | 37.080 | 72.420 | 2.0 |
| `histogram_bins` | 34.583 | 67.273 | 1.9 | 34.625 | 64.289 | 1.9 | 34.752 | 70.673 | 2.0 |
| `prefix_scan` | 18.922 | 31.128 | 1.6 | 18.960 | 31.632 | 1.7 | 19.134 | 35.385 | 1.8 |
| `binary_search` | 27.537 | 77.082 | 2.8 | 27.734 | 74.295 | 2.7 | 31.837 | 84.022 | 2.6 |
| `sort_window` | 23.793 | 58.993 | 2.5 | 23.832 | 49.583 | 2.1 | 23.444 | 55.447 | 2.4 |
| `bloom_filter` | 15.294 | 42.268 | 2.8 | 15.811 | 37.731 | 2.4 | 16.057 | 43.036 | 2.7 |
| `hash_join` | 22.476 | 55.143 | 2.5 | 23.744 | 65.438 | 2.8 | 24.035 | 64.697 | 2.7 |
| `sieve` | 16.105 | 54.818 | 3.4 | 15.874 | 48.463 | 3.1 | 15.699 | 48.043 | 3.1 |
| `fib` | 21.625 | 59.367 | 2.7 | 25.802 | 57.606 | 2.2 | 21.801 | 64.154 | 2.9 |
| `collatz` | 10.643 | 39.785 | 3.7 | 10.692 | 38.017 | 3.6 | 10.793 | 44.062 | 4.1 |
| `matmul` | 34.876 | 50.817 | 1.5 | 35.732 | 44.894 | 1.3 | 35.536 | 52.468 | 1.5 |
| `json_parse` | 6.689 | 42.397 | 6.3 | 7.088 | 33.837 | 4.8 | 9.335 | 47.802 | 5.1 |
| `nbody` | 35.804 | 65.462 | 1.8 | 35.936 | 62.953 | 1.8 | 34.201 | 65.840 | 1.9 |

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
| `lcg` | 1.5 | — | 1.5 | 1.0 |
| `packet_classifier` | 1.3 | — | 1.3 | 0.9 |
| `ring_write` | 1.6 | — | 1.7 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.8 | 1.2 |
| `prefix_scan` | 1.2 | — | 1.5 | — |
| `binary_search` | 2.6 | — | 2.6 | 1.8 |
| `sort_window` | 2.2 | — | 1.9 | — |
| `bloom_filter` | 2.4 | — | 2.2 | — |
| `hash_join` | 2.2 | — | 2.7 | 1.6 |
| `sieve` | 3.1 | — | 2.9 | — |
| `fib` | 2.5 | — | 2.1 | 1.7 |
| `collatz` | 3.3 | — | 3.4 | — |
| `matmul` | 1.2 | — | 1.1 | — |
| `json_parse` | 6.1 | — | 4.8 | — |
| `nbody` | 1.6 | — | 1.6 | 1.1 |

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
| _(floor: empty program)_ | _2.215_ | _0.2_ | _1.8_ | _2.148_ | _2.434_ |
| `lcg` | 36.387 | 0.6 | 1.1 | 36.545 | 36.541 |
| `packet_classifier` | 55.886 | 0.8 | 1.1 | 55.971 | 55.163 |
| `ring_write` | 47.529 | 0.7 | 1.3 | 47.702 | 47.634 |
| `histogram_bins` | 48.829 | 0.7 | 1.4 | 51.109 | 51.501 |
| `prefix_scan` | 11.512 | 0.4 | 0.6 | 13.402 | 11.519 |
| `binary_search` | 67.613 | 0.9 | 2.5 | 65.905 | 89.423 |
| `sort_window` | 63.197 | 1.1 | 2.7 | 68.958 | 68.960 |
| `bloom_filter` | 20.557 | 0.5 | 1.3 | 21.986 | 28.178 |
| `hash_join` | 51.177 | 0.9 | 2.3 | 53.109 | 53.250 |
| `sieve` | 33.867 | 0.6 | 2.1 | 36.190 | 33.491 |
| `fib` | 76.278 | 1.3 | 3.5 | 71.075 | 59.993 |
| `collatz` | 23.804 | 0.6 | 2.2 | 23.106 | 23.914 |
| `matmul` | 25.225 | 0.5 | 0.7 | 27.900 | 27.931 |
| `json_parse` | 39.782 | 0.9 | 5.9 | 17.904 | 84.526 |
| `nbody` | 75.027 | 1.1 | 2.1 | 62.305 | 76.871 |

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
| _(floor: empty program)_ | _1073_ | _1394_ | _+30 %_ | _9.105_ | _108.978_ | _+1097 %_ |
| `lcg` | 1093 | 1394 | +28 % | 56.980 | 138.004 | +142 % |
| `packet_classifier` | 1093 | 1394 | +28 % | 69.602 | 156.172 | +124 % |
| `ring_write` | 1093 | 1394 | +28 % | 67.618 | 150.320 | +122 % |
| `histogram_bins` | 1093 | 1395 | +28 % | 67.273 | 149.452 | +122 % |
| `prefix_scan` | 1094 | 1395 | +28 % | 31.128 | 113.649 | +265 % |
| `binary_search` | 1093 | 1394 | +28 % | 77.082 | 158.806 | +106 % |
| `sort_window` | 1094 | 1395 | +28 % | 58.993 | 143.501 | +143 % |
| `bloom_filter` | 1093 | 1395 | +28 % | 42.268 | 120.126 | +184 % |
| `hash_join` | 1095 | 1397 | +28 % | 55.143 | 141.768 | +157 % |
| `sieve` | 1093 | 1394 | +28 % | 54.818 | 134.191 | +145 % |
| `fib` | 1093 | 1394 | +28 % | 59.367 | 140.361 | +136 % |
| `collatz` | 1093 | 1394 | +28 % | 39.785 | 121.392 | +205 % |
| `matmul` | 1093 | 1394 | +28 % | 50.817 | 137.883 | +171 % |
| `json_parse` | 1119 | 1417 | +27 % | 42.397 | 126.326 | +198 % |
| `nbody` | 1095 | 1396 | +27 % | 65.462 | 144.765 | +121 % |

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
| _(floor: empty program)_ | _2.301_ | _81.919_ | _50.797_ | _52.939_ | _36.210_ | _47.128_ | _59.050_ |
| `lcg` | 2.554 | 90.126 | 50.299 | 58.867 | 36.430 | 52.049 | 62.793 |
| `packet_classifier` | 2.539 | 89.623 | 50.320 | 66.122 | 34.896 | 52.731 | 63.025 |
| `ring_write` | 2.641 | 88.439 | 48.933 | 59.743 | 36.538 | 53.047 | 63.561 |
| `histogram_bins` | 2.689 | 90.220 | 49.999 | 61.048 | 36.074 | 54.106 | 64.761 |
| `prefix_scan` | 2.721 | 93.144 | 50.961 | 63.460 | 35.528 | 54.560 | 66.053 |
| `binary_search` | 2.859 | 93.554 | 51.310 | 60.723 | 35.433 | 56.787 | 67.261 |
| `sort_window` | 2.883 | 98.588 | 53.083 | 66.494 | 35.416 | 60.434 | 70.411 |
| `bloom_filter` | 3.081 | 96.391 | 54.090 | 66.601 | 36.304 | 57.168 | 67.738 |
| `hash_join` | 5.069 | 179.358 | 115.276 | 95.894 | 35.884 | 82.911 | 94.239 |
| `sieve` | 2.745 | 94.647 | 70.907 | 66.763 | 37.543 | 60.319 | 70.824 |
| `fib` | 2.526 | 88.100 | 51.021 | 60.545 | 36.329 | 51.464 | 62.647 |
| `collatz` | 2.697 | 93.103 | 51.813 | 62.126 | 53.397 | 54.591 | 66.134 |
| `matmul` | 2.972 | 97.930 | 51.895 | 69.240 | 36.141 | 70.936 | 77.909 |
| `json_parse` | 40.001 | 457.198 | 119.252 | 99.474 | 37.056 | 138.927 | 123.078 |
| `nbody` | 4.077 | 105.657 | 58.710 | 80.682 | 40.764 | 72.465 | 85.481 |

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
