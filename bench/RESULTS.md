# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-11T20:27:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `7d3e817093ccdee3c1558f1569e846236ea774c7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34643819439 |
| NURL | `v0.63.0-9-g7d3e8170` |
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
| _(floor: empty program)_ | _1.422_ | _1.404_ | _1.648_ | _23.277_ | _17.186_ |
| `lcg` | **39.096** | 39.106 | 39.404 | 2052.762 | 5278.799 |
| `packet_classifier` | 56.327 | **56.306** | 56.551 | 162.961 | 4527.456 |
| `ring_write` | **42.302** | 42.328 | 42.494 | 66.916 | 6296.973 |
| `histogram_bins` | **39.486** | 40.562 | 39.674 | 67.042 | 6122.295 |
| `prefix_scan` | 21.632 | **21.605** | 21.779 | 66.196 | 4450.614 |
| `binary_search` | 39.458 | 38.195 | **37.060** | 105.246 | 6161.943 |
| `sort_window` | 26.524 | **26.501** | 26.771 | 196.456 | 11301.058 |
| `bloom_filter` | **16.539** | 17.977 | 18.312 | 2858.509 | 7679.049 |
| `hash_join` | **27.076** | 27.969 | 29.487 | 3435.043 | 8527.314 |
| `sieve` | 20.995 | **20.365** | 20.629 | 67.071 | 3250.863 |
| `fib` | **25.213** | 29.993 | 25.278 | 131.635 | 1364.734 |
| `collatz` | 12.250 | **12.201** | 12.412 | 50.993 | 722.112 |
| `matmul` | **33.428** | 33.455 | 33.732 | 78.225 | 3268.714 |
| `json_parse` | 9.901 | **8.576** | 11.416 | 35.685 | 39.159 |
| `nbody` | 25.061 | 39.747 | **24.090** | 101.408 | 3128.714 |

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
| _(floor: empty program)_ | _3.188_ | _94.784_ | _**97.972**_ | _61.152_ | _75.216_ | _60.421_ |
| `lcg` | 3.306 | 106.611 | **109.917** | 59.236 | 86.889 | 68.062 |
| `packet_classifier` | 3.590 | 112.476 | **116.066** | 61.809 | 103.354 | 70.458 |
| `ring_write` | 3.641 | 111.527 | **115.168** | 61.670 | 93.816 | 70.480 |
| `histogram_bins` | 3.721 | 117.484 | **121.205** | 59.852 | 107.673 | 77.206 |
| `prefix_scan` | 3.755 | 109.141 | **112.896** | 59.319 | 96.230 | 72.173 |
| `binary_search` | 4.009 | 110.241 | **114.250** | 60.889 | 92.631 | 74.276 |
| `sort_window` | 4.100 | 110.174 | **114.274** | 59.337 | 100.376 | 78.696 |
| `bloom_filter` | 4.580 | 112.166 | **116.746** | 60.400 | 98.907 | 73.855 |
| `hash_join` | 8.812 | 261.727 | **270.539** | 65.563 | 219.876 | 124.504 |
| `sieve` | 3.924 | 115.256 | **119.180** | 62.603 | 105.555 | 81.487 |
| `fib` | 3.347 | 106.582 | **109.929** | 60.031 | 90.646 | 66.027 |
| `collatz` | 3.621 | 111.985 | **115.606** | 61.130 | 93.339 | 70.439 |
| `matmul` | 4.318 | 111.477 | **115.795** | 61.640 | 107.691 | 94.292 |
| `json_parse` | 95.326 | 469.719 | **565.045** | 152.442 | 158.020 | 174.181 |
| `nbody` | 6.204 | 128.132 | **134.336** | 62.074 | 126.813 | 114.511 |

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
