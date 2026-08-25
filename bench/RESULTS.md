# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-25T22:34:55Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `1de1e2b44a96a7284d4b16b8809bf26eb6f6cd21` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/32906457197 |
| NURL | `v0.52.0-8-g1de1e2b4` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.0 (88d9e12ae 2026-08-18) |
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
| _(floor: empty program)_ | _1.564_ | _1.524_ | _1.765_ | _25.198_ | _19.074_ |
| `lcg` | 44.100 | **44.042** | 44.383 | 1820.088 | 5812.410 |
| `packet_classifier` | 63.509 | **63.472** | 63.688 | 156.425 | 4660.108 |
| `ring_write` | **47.593** | 47.656 | 47.809 | 73.178 | 6550.965 |
| `histogram_bins` | **44.581** | 44.624 | 44.871 | 76.541 | 6463.499 |
| `prefix_scan` | **24.423** | 24.490 | 24.755 | 72.862 | 4812.881 |
| `binary_search` | **33.287** | 35.724 | 36.725 | 112.667 | 7077.669 |
| `sort_window` | 30.030 | **29.974** | 30.323 | 165.325 | 11238.281 |
| `bloom_filter` | 19.687 | **18.672** | 20.711 | 2809.912 | 7930.164 |
| `hash_join` | **27.620** | 28.561 | 30.081 | 3419.820 | 8271.466 |
| `sieve` | 20.510 | **20.120** | 20.375 | 71.401 | 3832.957 |
| `fib` | **27.833** | 33.088 | 28.065 | 142.048 | 1289.234 |
| `collatz` | 13.688 | **13.656** | 13.821 | 53.053 | 752.859 |
| `matmul` | 46.375 | 46.557 | **45.577** | 84.859 | 3316.796 |
| `json_parse` | **8.686** | 8.861 | 12.103 | 39.698 | 40.064 |
| `nbody` | 26.703 | 45.012 | **26.328** | 95.971 | 3211.032 |

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
| _(floor: empty program)_ | _2.962_ | _101.231_ | _**104.193**_ | _64.513_ | _87.798_ | _66.835_ |
| `lcg` | 3.176 | 104.230 | **107.406** | 64.470 | 98.887 | 75.429 |
| `packet_classifier` | 3.260 | 106.068 | **109.328** | 66.683 | 101.217 | 75.066 |
| `ring_write` | 3.327 | 107.085 | **110.412** | 65.414 | 101.902 | 77.273 |
| `histogram_bins` | 3.424 | 123.297 | **126.721** | 65.208 | 117.094 | 83.818 |
| `prefix_scan` | 3.440 | 109.747 | **113.187** | 65.867 | 106.624 | 82.003 |
| `binary_search` | 3.550 | 111.784 | **115.334** | 64.908 | 105.016 | 82.435 |
| `sort_window` | 3.684 | 116.874 | **120.558** | 66.335 | 113.103 | 88.633 |
| `bloom_filter` | 3.868 | 112.933 | **116.801** | 65.943 | 111.789 | 84.476 |
| `hash_join` | 6.266 | 253.434 | **259.700** | 67.817 | 217.048 | 130.462 |
| `sieve` | 3.453 | 107.124 | **110.577** | 65.866 | 110.573 | 89.048 |
| `fib` | 3.117 | 103.712 | **106.829** | 64.409 | 99.196 | 72.772 |
| `collatz` | 3.409 | 109.031 | **112.440** | 65.361 | 100.362 | 77.740 |
| `matmul` | 3.686 | 110.580 | **114.266** | 66.031 | 111.738 | 98.920 |
| `json_parse` | 50.989 | 418.189 | **469.178** | 114.383 | 165.069 | 185.213 |
| `nbody` | 5.057 | 136.658 | **141.715** | 66.621 | 134.748 | 109.903 |

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
