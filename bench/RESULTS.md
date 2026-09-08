# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-08T18:46:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `92b54046aa11425e1f822042b4b18f44abf258b1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34264545353 |
| NURL | `v0.61.1-10-g92b54046` |
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
| _(floor: empty program)_ | _1.466_ | _1.442_ | _1.649_ | _23.610_ | _17.179_ |
| `lcg` | **38.979** | 39.033 | 39.172 | 2055.466 | 5244.849 |
| `packet_classifier` | 56.154 | **56.148** | 56.413 | 161.950 | 4334.001 |
| `ring_write` | **42.241** | 42.327 | 42.362 | 66.670 | 6270.717 |
| `histogram_bins` | **39.525** | 40.589 | 39.592 | 67.574 | 6062.787 |
| `prefix_scan` | 21.699 | **21.652** | 21.690 | 65.750 | 4498.846 |
| `binary_search` | 39.502 | 38.413 | **36.935** | 106.841 | 5839.767 |
| `sort_window` | 26.533 | **26.512** | 26.690 | 198.890 | 13002.383 |
| `bloom_filter` | 17.859 | **17.833** | 18.374 | 2844.286 | 7810.118 |
| `hash_join` | **26.925** | 28.148 | 29.537 | 3414.455 | 8402.571 |
| `sieve` | **17.873** | 19.222 | 18.099 | 67.856 | 3413.428 |
| `fib` | **25.044** | 29.721 | 25.194 | 133.889 | 1341.902 |
| `collatz` | 12.400 | **12.230** | 12.408 | 52.377 | 718.960 |
| `matmul` | 39.585 | 34.855 | **34.521** | 80.016 | 3128.463 |
| `json_parse` | 9.070 | **8.649** | 11.610 | 36.865 | 40.113 |
| `nbody` | 25.190 | 39.683 | **24.003** | 103.592 | 3089.943 |

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
| _(floor: empty program)_ | _2.775_ | _96.396_ | _**99.171**_ | _59.742_ | _79.154_ | _56.129_ |
| `lcg` | 2.876 | 107.454 | **110.330** | 59.384 | 89.659 | 61.728 |
| `packet_classifier` | 2.909 | 108.288 | **111.197** | 59.545 | 92.198 | 61.410 |
| `ring_write` | 3.098 | 113.330 | **116.428** | 60.453 | 93.015 | 62.723 |
| `histogram_bins` | 3.154 | 121.984 | **125.138** | 60.498 | 112.004 | 72.005 |
| `prefix_scan` | 3.190 | 110.866 | **114.056** | 59.673 | 98.545 | 67.280 |
| `binary_search` | 3.299 | 112.941 | **116.240** | 60.735 | 96.555 | 68.632 |
| `sort_window` | 3.365 | 116.570 | **119.935** | 62.037 | 106.110 | 72.529 |
| `bloom_filter` | 3.878 | 122.042 | **125.920** | 65.618 | 110.765 | 73.652 |
| `hash_join` | 6.283 | 271.062 | **277.345** | 68.575 | 236.170 | 123.236 |
| `sieve` | 3.518 | 117.633 | **121.151** | 64.580 | 112.931 | 80.589 |
| `fib` | 3.063 | 116.925 | **119.988** | 65.320 | 99.334 | 66.231 |
| `collatz` | 3.288 | 125.803 | **129.091** | 63.961 | 97.883 | 68.903 |
| `matmul` | 3.606 | 120.250 | **123.856** | 66.394 | 118.341 | 90.686 |
| `json_parse` | 58.910 | 471.246 | **530.156** | 123.318 | 173.737 | 179.629 |
| `nbody` | 5.038 | 140.702 | **145.740** | 67.502 | 144.717 | 100.337 |

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
