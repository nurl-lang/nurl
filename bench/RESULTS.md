# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-08-16T16:18:55Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `bae024e4ddcb3e0e215aba3d24234e8156112466` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/31958014713 |
| NURL | `v0.44.1-2-gbae024e4` |
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
| _(floor: empty program)_ | _1.811_ | _1.848_ | _2.007_ | _24.428_ | _17.963_ |
| `lcg` | **44.242** | 44.305 | 44.504 | 1821.007 | 5327.231 |
| `packet_classifier` | **63.691** | 63.782 | 63.894 | 157.424 | 4523.737 |
| `ring_write` | **47.775** | 47.910 | 48.036 | 73.167 | 6749.890 |
| `histogram_bins` | **44.813** | 44.914 | 44.955 | 76.869 | 6722.549 |
| `prefix_scan` | **24.648** | 24.716 | 24.848 | 71.038 | 4747.553 |
| `binary_search` | **34.291** | 36.019 | 46.276 | 111.239 | 7189.654 |
| `sort_window` | **30.226** | 31.049 | 30.439 | 173.068 | 11687.745 |
| `bloom_filter` | **19.944** | 20.578 | 20.915 | 2762.451 | 7919.269 |
| `hash_join` | **27.879** | 30.932 | 31.257 | 3457.778 | 8339.611 |
| `sieve` | 20.657 | **20.287** | 20.596 | 71.175 | 3538.955 |
| `fib` | **28.134** | 33.469 | 29.457 | 141.779 | 1289.121 |
| `collatz` | 13.935 | **13.916** | 14.001 | 52.489 | 751.556 |
| `matmul` | **45.368** | 46.128 | 46.589 | 85.536 | 3406.256 |
| `json_parse` | **9.007** | 9.076 | 12.260 | 39.280 | 38.463 |
| `nbody` | **26.962** | 46.430 | 44.245 | 97.128 | 3226.617 |

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
| _(floor: empty program)_ | _3.112_ | _98.720_ | _**101.832**_ | _63.854_ | _65.446_ | _64.508_ |
| `lcg` | 3.309 | 98.775 | **102.084** | 63.787 | 71.488 | 72.770 |
| `packet_classifier` | 3.413 | 102.509 | **105.922** | 65.606 | 75.482 | 73.801 |
| `ring_write` | 3.525 | 101.111 | **104.636** | 64.339 | 74.228 | 75.276 |
| `histogram_bins` | 3.632 | 126.427 | **130.059** | 66.708 | 78.615 | 77.369 |
| `prefix_scan` | 3.688 | 107.937 | **111.625** | 65.023 | 77.333 | 76.897 |
| `binary_search` | 3.806 | 111.831 | **115.637** | 65.929 | 76.288 | 79.280 |
| `sort_window` | 3.861 | 113.237 | **117.098** | 65.674 | 81.127 | 83.010 |
| `bloom_filter` | 4.104 | 111.213 | **115.317** | 65.983 | 82.733 | 84.892 |
| `hash_join` | 6.452 | 253.159 | **259.611** | 68.199 | 121.448 | 114.815 |
| `sieve` | 3.682 | 105.082 | **108.764** | 64.880 | 83.421 | 85.002 |
| `fib` | 3.387 | 100.437 | **103.824** | 65.003 | 73.207 | 71.836 |
| `collatz` | 3.561 | 103.020 | **106.581** | 64.572 | 73.659 | 75.446 |
| `matmul` | 3.891 | 107.465 | **111.356** | 65.108 | 85.664 | 99.922 |
| `json_parse` | 51.175 | 417.581 | **468.756** | 114.618 | 127.948 | 190.311 |
| `nbody` | 5.191 | 134.695 | **139.886** | 67.857 | 101.000 | 99.351 |

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
