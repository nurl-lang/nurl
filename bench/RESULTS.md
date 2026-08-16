# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T10:23:00Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0f6234d98995a3b5afcd4ae230b4bb376286adbd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31941307502 |
| NURL | `v0.43.0-21-g0f6234d9` |
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
| _(floor: empty program)_ | _1.676_ | _1.716_ | _1.886_ | _23.474_ | _16.905_ |
| `lcg` | **39.269** | 39.271 | 39.348 | 2071.237 | 5110.005 |
| `packet_classifier` | **56.311** | 56.462 | 56.555 | 161.254 | 4588.537 |
| `ring_write` | **42.357** | 42.516 | 42.515 | 65.420 | 6599.438 |
| `histogram_bins` | **39.706** | 41.398 | 39.791 | 65.618 | 6031.252 |
| `prefix_scan` | **21.845** | 21.897 | 22.091 | 65.128 | 4571.739 |
| `binary_search` | **36.383** | 38.395 | 43.365 | 106.337 | 6130.640 |
| `sort_window` | **26.769** | 27.495 | 27.119 | 197.358 | 14074.286 |
| `bloom_filter` | **18.062** | 18.333 | 18.549 | 2830.547 | 7441.869 |
| `hash_join` | **27.191** | 30.272 | 30.012 | 3447.510 | 8415.160 |
| `sieve` | 18.958 | 18.380 | **18.249** | 65.484 | 3184.636 |
| `fib` | **25.486** | 30.107 | 28.285 | 131.855 | 1360.469 |
| `collatz` | 12.534 | **12.512** | 12.711 | 50.038 | 713.869 |
| `matmul` | **33.505** | 33.706 | 33.808 | 77.272 | 3042.194 |
| `json_parse` | 9.126 | **8.845** | 11.744 | 36.545 | 37.680 |
| `nbody` | **25.398** | 40.944 | 39.219 | 101.647 | 3486.767 |

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
| _(floor: empty program)_ | _2.885_ | _88.804_ | _**91.689**_ | _58.667_ | _58.145_ | _65.353_ |
| `lcg` | 2.962 | 91.009 | **93.971** | 57.979 | 65.252 | 68.810 |
| `packet_classifier` | 3.035 | 92.360 | **95.395** | 57.912 | 67.522 | 68.132 |
| `ring_write` | 3.201 | 92.242 | **95.443** | 58.863 | 68.977 | 69.917 |
| `histogram_bins` | 3.234 | 113.028 | **116.262** | 58.250 | 70.300 | 73.036 |
| `prefix_scan` | 3.249 | 98.270 | **101.519** | 58.056 | 72.335 | 72.511 |
| `binary_search` | 3.443 | 101.920 | **105.363** | 58.146 | 70.344 | 74.488 |
| `sort_window` | 3.490 | 105.135 | **108.625** | 59.133 | 74.948 | 79.622 |
| `bloom_filter` | 3.679 | 100.843 | **104.522** | 58.188 | 76.604 | 75.215 |
| `hash_join` | 6.113 | 255.184 | **261.297** | 62.466 | 118.616 | 113.450 |
| `sieve` | 3.270 | 97.195 | **100.465** | 57.978 | 78.225 | 79.225 |
| `fib` | 3.046 | 92.616 | **95.662** | 58.426 | 64.897 | 68.772 |
| `collatz` | 3.181 | 94.705 | **97.886** | 58.218 | 67.077 | 69.857 |
| `matmul` | 3.571 | 100.257 | **103.828** | 58.618 | 79.686 | 92.084 |
| `json_parse` | 51.064 | 431.841 | **482.905** | 108.893 | 124.175 | 179.754 |
| `nbody` | 4.880 | 123.996 | **128.876** | 60.282 | 95.925 | 93.380 |

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
