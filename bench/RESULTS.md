# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-30T04:02:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `e94181b06ef32920ed9c441d88c5538ecb12de86` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/36666732139 |
| NURL | `v0.67.0-5-ge94181b0` |
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
| _(floor: empty program)_ | _1.224_ | _1.208_ | _1.392_ | _17.814_ | _13.706_ |
| `lcg` | 34.211 | **34.133** | 34.311 | 1411.981 | 4083.154 |
| `packet_classifier` | 49.256 | **49.204** | 49.401 | 123.339 | 3565.781 |
| `ring_write` | 36.910 | **36.906** | 37.066 | 56.387 | 4913.191 |
| `histogram_bins` | 34.634 | **34.577** | 34.729 | 57.787 | 4914.454 |
| `prefix_scan` | 18.896 | **18.867** | 19.057 | 55.530 | 3742.880 |
| `binary_search` | 32.136 | **27.706** | 28.377 | 86.339 | 4881.237 |
| `sort_window` | 23.321 | **23.250** | 23.355 | 127.981 | 8482.624 |
| `bloom_filter` | **13.407** | 14.465 | 15.985 | 2123.716 | 6515.522 |
| `hash_join` | **21.400** | 22.155 | 23.383 | 2692.409 | 6380.940 |
| `sieve` | 15.915 | **15.543** | 15.688 | 54.871 | 2962.468 |
| `fib` | **21.616** | 25.716 | 21.768 | 110.941 | 999.615 |
| `collatz` | 10.620 | **10.528** | 10.722 | 40.087 | 583.475 |
| `matmul` | 35.575 | 35.416 | **35.414** | 65.109 | 2721.683 |
| `json_parse` | **6.436** | 6.833 | 9.370 | 28.337 | 29.962 |
| `nbody` | 20.721 | 34.852 | **20.348** | 74.952 | 2546.153 |

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
| _(floor: empty program)_ | _3.056_ | _83.191_ | _**86.247**_ | _51.081_ | _67.768_ | _51.433_ |
| `lcg` | 3.036 | 89.929 | **92.965** | 51.136 | 76.028 | 57.749 |
| `packet_classifier` | 3.146 | 91.251 | **94.397** | 51.777 | 76.875 | 57.591 |
| `ring_write` | 3.359 | 92.145 | **95.504** | 52.204 | 77.997 | 58.926 |
| `histogram_bins` | 3.432 | 98.059 | **101.491** | 52.324 | 90.559 | 65.767 |
| `prefix_scan` | 3.479 | 92.512 | **95.991** | 51.892 | 82.206 | 62.257 |
| `binary_search` | 3.636 | 93.051 | **96.687** | 52.696 | 79.855 | 63.413 |
| `sort_window` | 3.775 | 95.666 | **99.441** | 53.615 | 86.931 | 67.893 |
| `bloom_filter` | 4.161 | 97.171 | **101.332** | 54.045 | 85.366 | 64.519 |
| `hash_join` | 7.605 | 200.267 | **207.872** | 56.831 | 169.219 | 106.476 |
| `sieve` | 3.521 | 91.044 | **94.565** | 52.126 | 85.726 | 67.935 |
| `fib` | 3.140 | 92.090 | **95.230** | 52.569 | 76.292 | 57.777 |
| `collatz` | 3.389 | 94.001 | **97.390** | 52.765 | 77.617 | 59.703 |
| `matmul` | 3.873 | 92.567 | **96.440** | 52.523 | 87.697 | 77.708 |
| `json_parse` | 79.524 | 339.620 | **419.144** | 129.557 | 127.968 | 144.028 |
| `nbody` | 5.472 | 106.569 | **112.041** | 54.534 | 103.550 | 85.039 |

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
