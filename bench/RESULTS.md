# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-13T20:58:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16372428 KiB |
| Commit | `a7146d7d90a106a97e8b205454fdeb42f572cf4d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34782183097 |
| NURL | `v0.65.0-4-ga7146d7d` |
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
| _(floor: empty program)_ | _1.105_ | _1.091_ | _1.326_ | _20.466_ | _13.884_ |
| `lcg` | **35.475** | 38.510 | 39.081 | 1418.832 | 3925.177 |
| `packet_classifier` | 62.746 | 63.878 | **61.801** | 155.411 | 3217.840 |
| `ring_write` | 40.331 | 39.025 | **38.876** | 56.767 | 4649.666 |
| `histogram_bins` | 36.489 | 38.683 | **36.211** | 61.099 | 4593.133 |
| `prefix_scan` | **19.359** | 19.598 | 19.527 | 57.185 | 3365.657 |
| `binary_search` | 34.896 | **27.607** | 27.729 | 96.365 | 4918.104 |
| `sort_window` | 34.979 | **34.406** | 35.416 | 160.829 | 8581.921 |
| `bloom_filter` | 13.575 | **12.494** | 12.769 | 2208.671 | 5701.160 |
| `hash_join` | **20.515** | 23.059 | 22.192 | 2724.532 | 6439.771 |
| `sieve` | 34.490 | **33.213** | 34.241 | 75.682 | 2380.544 |
| `fib` | 25.750 | 26.393 | **25.408** | 100.733 | 802.666 |
| `collatz` | **13.433** | 14.765 | 14.832 | 51.648 | 510.990 |
| `matmul` | 18.036 | **17.894** | 18.248 | 64.764 | 2202.788 |
| `json_parse` | 7.734 | **6.549** | 8.813 | 28.886 | 29.320 |
| `nbody` | **19.456** | 27.943 | 19.517 | 71.863 | 1988.175 |

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
| _(floor: empty program)_ | _2.532_ | _67.854_ | _**70.386**_ | _44.514_ | _51.764_ | _49.807_ |
| `lcg` | 2.692 | 80.508 | **83.200** | 42.616 | 63.707 | 58.380 |
| `packet_classifier` | 3.115 | 78.776 | **81.891** | 43.930 | 63.844 | 59.422 |
| `ring_write` | 3.339 | 80.980 | **84.319** | 43.270 | 61.081 | 55.815 |
| `histogram_bins` | 3.170 | 87.297 | **90.467** | 41.700 | 77.569 | 63.694 |
| `prefix_scan` | 3.342 | 80.925 | **84.267** | 43.777 | 63.482 | 57.270 |
| `binary_search` | 3.303 | 75.847 | **79.150** | 41.917 | 60.842 | 63.987 |
| `sort_window` | 3.545 | 81.162 | **84.707** | 43.561 | 66.994 | 64.954 |
| `bloom_filter` | 3.953 | 82.960 | **86.913** | 43.479 | 65.938 | 63.242 |
| `hash_join` | 7.594 | 192.845 | **200.439** | 49.115 | 154.317 | 106.827 |
| `sieve` | 3.565 | 80.690 | **84.255** | 44.670 | 67.988 | 65.919 |
| `fib` | 2.819 | 77.240 | **80.059** | 41.574 | 58.113 | 53.088 |
| `collatz` | 3.069 | 78.757 | **81.826** | 43.076 | 62.489 | 56.573 |
| `matmul` | 3.642 | 79.757 | **83.399** | 43.269 | 73.209 | 80.818 |
| `json_parse` | 92.514 | 364.092 | **456.606** | 137.933 | 112.267 | 160.942 |
| `nbody` | 5.314 | 95.970 | **101.284** | 43.872 | 91.586 | 85.511 |

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
