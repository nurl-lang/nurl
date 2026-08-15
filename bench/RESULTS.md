# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-15T03:23:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `6c7fb5beb2fa371a554a84afb29bcd6486340709` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31861517738 |
| NURL | `v0.42.0-24-g6c7fb5be` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.23.2 |
| Python | Python 3.12.3 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2`, Rust `-C opt-level=2` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.219_ | _1.265_ | _1.329_ | _17.320_ | _11.522_ |
| `lcg` | 34.171 | **33.390** | 33.404 | 1055.880 | 3174.423 |
| `packet_classifier` | **52.089** | 52.091 | 52.230 | 125.133 | 2653.182 |
| `ring_write` | 37.254 | 37.402 | **36.222** | 55.912 | 3795.868 |
| `histogram_bins` | 31.348 | **31.230** | 31.304 | 50.904 | 3601.832 |
| `prefix_scan` | **18.858** | 19.226 | 19.220 | 50.521 | 2690.601 |
| `binary_search` | **21.232** | 25.853 | 35.394 | 84.267 | 4166.717 |
| `sort_window` | **30.029** | 38.420 | 30.814 | 135.420 | 6784.011 |
| `bloom_filter` | **10.798** | 10.881 | 10.911 | 1857.474 | 4778.773 |
| `hash_join` | **17.980** | 19.822 | 20.080 | 2253.171 | 5137.856 |
| `sieve` | 32.774 | **32.441** | 33.205 | 66.484 | 1951.503 |
| `fib` | **17.475** | 20.428 | 19.382 | 83.178 | 664.917 |
| `collatz` | **11.350** | 11.528 | 12.242 | 44.096 | 419.209 |
| `matmul` | 15.623 | **15.249** | 15.283 | 54.193 | 1975.070 |
| `json_parse` | **5.620** | 6.161 | 7.137 | 23.728 | 24.299 |
| `nbody` | **18.086** | 26.269 | 24.079 | 66.384 | 1699.343 |

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
| _(floor: empty program)_ | _2.010_ | _57.109_ | _**59.119**_ | _37.504_ | _37.705_ | _48.770_ |
| `lcg` | 2.089 | 58.170 | **60.259** | 36.392 | 43.908 | 51.325 |
| `packet_classifier` | 2.194 | 57.753 | **59.947** | 37.442 | 40.988 | 52.940 |
| `ring_write` | 2.327 | 64.021 | **66.348** | 41.190 | 46.739 | 58.566 |
| `histogram_bins` | 2.410 | 79.651 | **82.061** | 40.090 | 50.556 | 55.035 |
| `prefix_scan` | 2.297 | 63.757 | **66.054** | 37.447 | 46.512 | 55.335 |
| `binary_search` | 2.418 | 67.469 | **69.887** | 38.826 | 44.348 | 59.318 |
| `sort_window` | 2.429 | 66.761 | **69.190** | 38.137 | 48.315 | 61.153 |
| `bloom_filter` | 2.544 | 62.804 | **65.348** | 36.431 | 47.800 | 55.990 |
| `hash_join` | 4.087 | 157.409 | **161.496** | 40.030 | 71.195 | 82.922 |
| `sieve` | 2.259 | 60.133 | **62.392** | 37.739 | 45.996 | 61.538 |
| `fib` | 2.097 | 56.908 | **59.005** | 37.829 | 40.455 | 50.146 |
| `collatz` | 2.227 | 59.777 | **62.004** | 36.699 | 42.808 | 53.476 |
| `matmul` | 2.464 | 64.493 | **66.957** | 37.785 | 48.027 | 71.262 |
| `json_parse` | 31.302 | 271.669 | **302.971** | 70.427 | 77.250 | 140.761 |
| `nbody` | 3.261 | 79.664 | **82.925** | 39.159 | 58.410 | 70.812 |

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
