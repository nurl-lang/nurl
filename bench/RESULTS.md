# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-07T13:18:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `7a639e99b775717f8e0d1dcc23d127ad673c6520` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34126211390 |
| NURL | `v0.61.0-11-g7a639e99` |
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
| _(floor: empty program)_ | _1.447_ | _1.469_ | _1.637_ | _23.417_ | _16.970_ |
| `lcg` | 39.133 | **38.981** | 39.306 | 2046.750 | 5380.412 |
| `packet_classifier` | 56.304 | **56.109** | 56.435 | 161.448 | 4320.622 |
| `ring_write` | **42.092** | 42.205 | 42.352 | 66.665 | 6369.469 |
| `histogram_bins` | **39.523** | 40.750 | 39.826 | 66.159 | 6431.652 |
| `prefix_scan` | **21.569** | 21.688 | 21.744 | 66.848 | 4825.047 |
| `binary_search` | 39.378 | 38.124 | **36.884** | 105.189 | 5970.394 |
| `sort_window` | **26.507** | 26.509 | 26.838 | 198.674 | 11228.614 |
| `bloom_filter` | 18.206 | **18.089** | 18.640 | 2843.164 | 7444.614 |
| `hash_join` | **27.109** | 27.872 | 29.319 | 3435.065 | 8434.194 |
| `sieve` | 18.742 | **18.124** | 18.452 | 66.267 | 3240.819 |
| `fib` | **25.069** | 29.751 | 25.415 | 131.905 | 1401.449 |
| `collatz` | 12.258 | **12.149** | 12.335 | 49.833 | 720.681 |
| `matmul` | 33.493 | **33.372** | 33.503 | 76.741 | 3546.382 |
| `json_parse` | 8.991 | **8.600** | 11.591 | 36.307 | 39.019 |
| `nbody` | 25.406 | 39.947 | **24.009** | 99.812 | 3130.383 |

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
| _(floor: empty program)_ | _2.631_ | _95.635_ | _**98.266**_ | _58.884_ | _80.423_ | _53.676_ |
| `lcg` | 2.763 | 104.611 | **107.374** | 57.747 | 89.874 | 60.564 |
| `packet_classifier` | 2.925 | 107.241 | **110.166** | 59.708 | 92.328 | 60.090 |
| `ring_write` | 2.979 | 107.654 | **110.633** | 58.364 | 90.055 | 60.305 |
| `histogram_bins` | 3.049 | 116.421 | **119.470** | 59.016 | 108.356 | 68.104 |
| `prefix_scan` | 3.098 | 109.257 | **112.355** | 58.002 | 96.545 | 64.649 |
| `binary_search` | 3.219 | 107.304 | **110.523** | 59.808 | 91.430 | 65.618 |
| `sort_window` | 3.328 | 111.631 | **114.959** | 58.961 | 104.259 | 69.896 |
| `bloom_filter` | 3.568 | 114.280 | **117.848** | 60.466 | 104.292 | 67.112 |
| `hash_join` | 6.188 | 262.614 | **268.802** | 64.894 | 219.664 | 114.930 |
| `sieve` | 3.174 | 113.375 | **116.549** | 60.794 | 105.454 | 72.827 |
| `fib` | 2.904 | 109.240 | **112.144** | 59.427 | 89.785 | 58.581 |
| `collatz` | 3.047 | 111.157 | **114.204** | 59.400 | 91.841 | 60.638 |
| `matmul` | 3.343 | 109.196 | **112.539** | 59.086 | 104.464 | 83.149 |
| `json_parse` | 57.207 | 455.655 | **512.862** | 115.476 | 160.402 | 165.788 |
| `nbody` | 4.812 | 128.905 | **133.717** | 61.833 | 128.512 | 91.111 |

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
