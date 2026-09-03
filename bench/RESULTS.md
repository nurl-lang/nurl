# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-03T17:34:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `6429a82d287c44d965f9b15693d9c794d8f26913` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33784840375 |
| NURL | `v0.59.0-8-g6429a82d` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.450_ | _1.409_ | _1.629_ | _24.411_ | _16.786_ |
| `lcg` | 38.948 | **38.942** | 39.222 | 2041.366 | 5083.643 |
| `packet_classifier` | 56.206 | **56.195** | 56.586 | 162.758 | 4515.868 |
| `ring_write` | **42.288** | 42.359 | 42.489 | 66.818 | 6142.597 |
| `histogram_bins` | **39.394** | 40.529 | 39.578 | 66.802 | 5997.886 |
| `prefix_scan` | 21.596 | **21.587** | 21.598 | 64.333 | 4654.333 |
| `binary_search` | 39.566 | 38.106 | **37.001** | 105.985 | 5952.040 |
| `sort_window` | **26.527** | 26.568 | 26.716 | 196.505 | 11404.789 |
| `bloom_filter` | 17.762 | **17.750** | 18.285 | 2826.619 | 7751.774 |
| `hash_join` | **26.835** | 27.758 | 29.168 | 3400.414 | 8339.913 |
| `sieve` | 20.325 | **19.590** | 19.985 | 65.342 | 3512.069 |
| `fib` | **24.986** | 29.759 | 25.350 | 131.918 | 1361.322 |
| `collatz` | 12.245 | **12.160** | 12.460 | 50.108 | 711.130 |
| `matmul` | 33.232 | **33.147** | 33.442 | 76.324 | 3348.494 |
| `json_parse` | 9.052 | **8.505** | 11.451 | 35.242 | 36.953 |
| `nbody` | 25.143 | 39.627 | **24.117** | 102.236 | 3028.899 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc` emits LLVM IR, then `clang`
lowers and links it against `stdlib/runtime.o`. **NURL total** is the
number comparable to the C and Rust columns: a cold compile, measured
against a wiped cache exactly as C and Rust pay their full cost every
time. **NURL rebuild** is the same compile again with the ThinLTO
cache warm — `nurl.sh`'s default on Linux (docs/BUILDING.md → The
ThinLTO cache) — which is what every build after the first costs; C
and Rust have no default equivalent (`ccache`/`sccache` are opt-in
add-ons). The floor row is what each toolchain costs for a program
that does nothing — for NURL that is dominated by the LTO link every
NURL binary pays for, so subtract it to read the marginal cost of the
benchmark itself. Node and Python have no column here: they compile
at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | NURL rebuild | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _2.657_ | _97.431_ | _**100.088**_ | _58.137_ | _77.127_ | _52.985_ |
| `lcg` | 2.794 | 105.492 | **108.286** | 57.770 | 88.742 | 60.262 |
| `packet_classifier` | 2.920 | 108.450 | **111.370** | 60.115 | 91.784 | 60.374 |
| `ring_write` | 2.993 | 109.502 | **112.495** | 59.484 | 94.914 | 62.176 |
| `histogram_bins` | 3.076 | 115.834 | **118.910** | 59.285 | 109.039 | 67.494 |
| `prefix_scan` | 3.130 | 108.469 | **111.599** | 57.792 | 97.170 | 63.441 |
| `binary_search` | 3.248 | 107.516 | **110.764** | 58.274 | 92.454 | 67.155 |
| `sort_window` | 3.361 | 110.369 | **113.730** | 58.900 | 101.318 | 70.982 |
| `bloom_filter` | 3.554 | 113.481 | **117.035** | 60.128 | 102.797 | 66.935 |
| `hash_join` | 6.198 | 270.336 | **276.534** | 63.864 | 217.957 | 113.614 |
| `sieve` | 3.111 | 110.280 | **113.391** | 59.915 | 103.010 | 71.146 |
| `fib` | 2.809 | 105.930 | **108.739** | 59.161 | 90.546 | 58.531 |
| `collatz` | 2.971 | 108.572 | **111.543** | 59.470 | 89.863 | 62.296 |
| `matmul` | 3.367 | 107.312 | **110.679** | 58.281 | 103.503 | 82.844 |
| `json_parse` | 56.829 | 457.615 | **514.444** | 113.269 | 160.117 | 162.799 |
| `nbody` | 4.705 | 127.194 | **131.899** | 60.123 | 128.352 | 91.072 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `8299504528805184357` | identical across 5 languages |
| `histogram_bins` | `1215643728` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `6152419568754618368` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |
| `nbody` | `4595260366167553674` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `nbody` is the counterweight to the row above, and the only row defined
  over IEEE-754 doubles rather than integers. That is the type JavaScript
  does have — its one numeric type is the double — so Node runs the same
  arithmetic as the compiled backends with no representation tax, and lands
  near 2x C instead of the 30-50x the BigInt rows cost it. It is also the
  only row whose critical path runs through the FPU's long-latency sqrt and
  divide units rather than the integer ALU. All five ports use the same
  operation order and the same struct-of-arrays layout, so the checksum —
  the final energy's bit pattern — is exact across all five.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
