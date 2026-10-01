# WebAssembly benchmark results — NURL native vs NURL wasm

Generated `2026-10-01T19:11:15Z` by `bench/wasmbench.sh`. **Do not edit by hand** —
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
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `97f7a6df0346d785f83d644f66c5dd4323f7e65a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36911987190 |
| NURL | `v0.68.0-4-g97f7a6df` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |

| Component | Value |
|---|---|
| NURL → wasm | `packages/wasmbuilder` (wasmbuilder 0.3.0), built from this repo |
| C → wasm | `zig 0.16.0 cc --target=wasm32-wasi` |
| Rust → wasm | `rustc --target wasm32-wasip1` |
| wasm runtime (reference) | `wasmtime 48.0.2 (e9f1ea232 2026-09-10)` — Cranelift JIT |
| wasm runtime (NURL) | `packages/nwasm` (nwasm 1.0.11 (pure NURL)) — template JIT + interpreter, built from this repo, `NURL_SPLIT=0` (release build; see below) |

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
| _(floor: empty program)_ | _1.224_ | _9.885_ | _8.1_ | _1.243_ | _6.360_ | _5.1_ | _1.384_ | _28.036_ | _20.3_ |
| `lcg` | 32.583 | 52.050 | 1.6 | 32.255 | 51.899 | 1.6 | 31.927 | 55.899 | 1.8 |
| `packet_classifier` | 52.704 | 60.697 | 1.2 | 55.294 | 59.931 | 1.1 | 55.302 | 64.922 | 1.2 |
| `ring_write` | 36.103 | 65.039 | 1.8 | 37.039 | 65.414 | 1.8 | 36.566 | 68.866 | 1.9 |
| `histogram_bins` | 34.892 | 66.549 | 1.9 | 34.835 | 63.260 | 1.8 | 34.367 | 67.954 | 2.0 |
| `prefix_scan` | 17.447 | 28.736 | 1.6 | 17.917 | 32.869 | 1.8 | 17.986 | 34.304 | 1.9 |
| `binary_search` | 24.795 | 75.448 | 3.0 | 24.885 | 70.299 | 2.8 | 37.338 | 78.834 | 2.1 |
| `sort_window` | 35.044 | 56.185 | 1.6 | 42.614 | 47.237 | 1.1 | 32.719 | 53.608 | 1.6 |
| `bloom_filter` | 11.703 | 38.200 | 3.3 | 12.092 | 31.812 | 2.6 | 12.088 | 34.917 | 2.9 |
| `hash_join` | 20.359 | 56.086 | 2.8 | 22.012 | 58.712 | 2.7 | 22.249 | 62.956 | 2.8 |
| `sieve` | 36.268 | 63.506 | 1.8 | 35.697 | 61.288 | 1.7 | 35.560 | 66.664 | 1.9 |
| `fib` | 19.933 | 55.617 | 2.8 | 23.468 | 50.458 | 2.2 | 23.753 | 59.147 | 2.5 |
| `collatz` | 12.526 | 37.587 | 3.0 | 12.176 | 37.330 | 3.1 | 13.079 | 42.196 | 3.2 |
| `matmul` | 16.814 | 39.547 | 2.4 | 16.462 | 37.007 | 2.2 | 16.664 | 43.384 | 2.6 |
| `json_parse` | 7.353 | 42.907 | 5.8 | 6.748 | 31.918 | 4.7 | 8.141 | 45.762 | 5.6 |
| `nbody` | 26.773 | 49.720 | 1.9 | 27.133 | 52.474 | 1.9 | 24.185 | 54.056 | 2.2 |

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
| `lcg` | 1.3 | — | 1.5 | — |
| `packet_classifier` | 1.0 | — | 1.0 | 0.7 |
| `ring_write` | 1.6 | — | 1.6 | 1.2 |
| `histogram_bins` | 1.7 | — | 1.7 | 1.2 |
| `prefix_scan` | 1.2 | — | 1.6 | — |
| `binary_search` | 2.8 | — | 2.7 | 1.4 |
| `sort_window` | 1.4 | — | 1.0 | — |
| `bloom_filter` | 2.7 | — | 2.3 | — |
| `hash_join` | 2.4 | — | 2.5 | 1.7 |
| `sieve` | 1.5 | — | 1.6 | 1.1 |
| `fib` | 2.4 | — | 2.0 | 1.4 |
| `collatz` | 2.5 | — | 2.8 | — |
| `matmul` | 1.9 | — | 2.0 | — |
| `json_parse` | 5.4 | — | 4.6 | — |
| `nbody` | 1.6 | — | 1.8 | — |

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
| _(floor: empty program)_ | _2.186_ | _0.2_ | _1.8_ | _2.092_ | _2.617_ |
| `lcg` | 35.257 | 0.7 | 1.1 | 35.702 | 36.120 |
| `packet_classifier` | 47.488 | 0.8 | 0.9 | 45.153 | 50.310 |
| `ring_write` | 45.824 | 0.7 | 1.3 | 44.771 | 44.780 |
| `histogram_bins` | 46.242 | 0.7 | 1.3 | 47.094 | 49.494 |
| `prefix_scan` | 12.750 | 0.4 | 0.7 | 11.600 | 13.736 |
| `binary_search` | 50.685 | 0.7 | 2.0 | 50.916 | 83.266 |
| `sort_window` | 83.090 | 1.5 | 2.4 | 41.981 | 44.803 |
| `bloom_filter` | 20.196 | 0.5 | 1.7 | 21.697 | 20.834 |
| `hash_join` | 49.899 | 0.9 | 2.5 | 50.556 | 55.874 |
| `sieve` | 52.233 | 0.8 | 1.4 | 55.117 | 50.507 |
| `fib` | 61.144 | 1.1 | 3.1 | 55.291 | 49.163 |
| `collatz` | 27.288 | 0.7 | 2.2 | 28.263 | 29.796 |
| `matmul` | 19.346 | 0.5 | 1.2 | 24.306 | 23.320 |
| `json_parse` | 38.181 | 0.9 | 5.2 | 15.065 | 75.869 |
| `nbody` | 50.162 | 1.0 | 1.9 | 48.861 | 54.023 |

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
| `json_parse` | 36 | 47 | 16 | 1007 | 4445 | 2159 |
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
| _(floor: empty program)_ | _4_ | _305_ | _+7934 %_ | _9.885_ | _108.289_ | _+995 %_ |
| `lcg` | 26 | 306 | +1077 % | 52.050 | 133.788 | +157 % |
| `packet_classifier` | 26 | 305 | +1079 % | 60.697 | 137.543 | +127 % |
| `ring_write` | 26 | 306 | +1076 % | 65.039 | 143.406 | +120 % |
| `histogram_bins` | 26 | 306 | +1074 % | 66.549 | 143.590 | +116 % |
| `prefix_scan` | 26 | 306 | +1061 % | 28.736 | 115.794 | +303 % |
| `binary_search` | 26 | 305 | +1072 % | 75.448 | 152.711 | +102 % |
| `sort_window` | 26 | 306 | +1062 % | 56.185 | 133.649 | +138 % |
| `bloom_filter` | 26 | 306 | +1067 % | 38.200 | 117.321 | +207 % |
| `hash_join` | 28 | 308 | +999 % | 56.086 | 137.949 | +146 % |
| `sieve` | 26 | 306 | +1076 % | 63.506 | 147.197 | +132 % |
| `fib` | 26 | 305 | +1080 % | 55.617 | 143.615 | +158 % |
| `collatz` | 26 | 305 | +1080 % | 37.587 | 118.792 | +216 % |
| `matmul` | 26 | 306 | +1065 % | 39.547 | 119.785 | +203 % |
| `json_parse` | 47 | 324 | +594 % | 42.907 | 128.532 | +200 % |
| `nbody` | 28 | 307 | +1005 % | 49.720 | 135.616 | +173 % |

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
| _(floor: empty program)_ | _3.063_ | _83.420_ | _39.324_ | _48.986_ | _31.630_ | _51.713_ | _61.220_ |
| `lcg` | 3.065 | 99.676 | 36.824 | 56.938 | 30.050 | 55.282 | 64.875 |
| `packet_classifier` | 2.968 | 93.806 | 38.688 | 73.159 | 47.822 | 54.962 | 64.637 |
| `ring_write` | 3.240 | 94.561 | 36.654 | 56.116 | 30.189 | 55.134 | 66.590 |
| `histogram_bins` | 3.193 | 94.526 | 35.897 | 56.729 | 30.556 | 56.605 | 67.090 |
| `prefix_scan` | 3.413 | 101.142 | 35.641 | 60.127 | 42.244 | 56.518 | 67.368 |
| `binary_search` | 3.448 | 100.315 | 39.787 | 58.755 | 31.312 | 60.148 | 73.167 |
| `sort_window` | 3.868 | 111.316 | 40.335 | 65.511 | 33.116 | 64.675 | 76.517 |
| `bloom_filter` | 4.046 | 106.624 | 38.434 | 64.600 | 47.548 | 61.504 | 70.628 |
| `hash_join` | 7.087 | 181.632 | 46.303 | 93.785 | 82.262 | 91.988 | 97.095 |
| `sieve` | 3.662 | 101.581 | 38.175 | 66.431 | 32.122 | 63.869 | 75.376 |
| `fib` | 3.190 | 97.316 | 38.227 | 56.471 | 46.742 | 56.897 | 67.005 |
| `collatz` | 3.303 | 98.597 | 35.759 | 55.237 | 30.920 | 55.870 | 66.287 |
| `matmul` | 3.832 | 103.572 | 37.256 | 65.089 | 31.049 | 72.078 | 81.037 |
| `json_parse` | 80.657 | 512.954 | 162.780 | 105.655 | 33.954 | 150.467 | 130.105 |
| `nbody` | 5.151 | 116.906 | 46.111 | 79.890 | 31.140 | 75.121 | 85.084 |

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
