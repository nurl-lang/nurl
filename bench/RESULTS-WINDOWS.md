# Benchmark results (Windows) — NURL vs C vs Rust vs Node vs Python

Generated `2026-07-27T09:12:12Z` by `bench/bench.ps1`, the Windows port of
`bench/bench.sh`. **Do not edit by hand** — the next run overwrites it.
The machine-readable form of this same run is
[`results/latest-windows.json`](results/latest-windows.json).

These are **not** the numbers the landing page publishes: that table comes
from the Linux CI run in [`RESULTS.md`](RESULTS.md) /
[`results/latest.json`](results/latest.json). Two things differ beyond the
host — NURL links without `-flto` here, because `build.bat` does not compile
`stdlib/runtime.o` to bitcode, and the link names `-lwinhttp` instead of
`-lm -lpthread`. Both match what a real `nurl.bat` build does on this
platform, which is the property worth measuring; both make the NURL column
incomparable to a Linux run cell-for-cell.

## Environment

| Item | Value |
|---|---|
| Host | `Windows AMD64` |
| OS | `Microsoft Windows 11 Pro 10.0.26200 AMD64` |
| CPU | 11th Gen Intel(R) Core(TM) i7-11850H @ 2.50GHz (16 logical cores) |
| Memory | 33250360 KiB |
| Commit | `1b8552a56ec3440f299144297322fd7bd11b0c25` |
| NURL | `v0.26.0-17-g1b8552a` |
| C | clang version 22.1.3 (https://github.com/llvm/llvm-project e9846648fd6183ee6d8cbdb4502213fcf902a211) |
| Rust | rustc 1.97.1 (8bab26f4f 2026-07-14) |
| Node | v22.16.0 |
| Python | Python 3.12.6 |

| Setting | Value |
|---|---|
| Optimisation | NURL/C `clang -O2` (no LTO), Rust `-C opt-level=2` |
| NURL link | `-lwinhttp -LC:\vcpkg\installed\x64-windows-static\lib -lzlib -LC:\vcpkg\installed\x64-windows-static\lib -lzstd` |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _17.974_ | _16.930_ | _16.894_ | _45.416_ | _34.080_ |
| `lcg` | 43.842 | **42.598** | 43.376 | 2691.907 | 4883.625 |
| `affine_mix` | **43.338** | 43.860 | 45.427 | 1801.460 | 5707.761 |
| `packet_classifier` | 56.976 | **54.543** | 54.823 | 149.417 | 3692.680 |
| `ring_write` | 46.586 | **43.584** | 44.457 | 79.780 | 6047.521 |
| `histogram_bins` | 46.700 | 46.549 | **44.944** | 80.052 | 5890.072 |
| `prefix_scan` | 33.603 | 32.084 | **31.011** | 82.763 | 4156.530 |
| `binary_search` | **38.135** | 39.071 | 47.589 | 114.913 | 5556.885 |
| `sort_window` | 56.797 | 73.591 | **43.306** | 180.255 | 9803.525 |
| `bloom_filter` | 27.923 | 27.381 | **26.781** | 3032.633 | 7399.137 |
| `hash_join` | 21.939 | 20.800 | **18.817** | 417.576 | 797.204 |
| `sieve` | 40.803 | **38.092** | 39.073 | 88.439 | 2887.155 |
| `fib` | 39.900 | **34.760** | 38.585 | 126.255 | 1135.616 |
| `collatz` | 26.092 | **24.686** | 27.535 | 74.279 | 721.317 |
| `matmul` | 28.820 | **28.188** | 30.106 | 83.410 | 2774.881 |
| `json_parse` | 38.834 | **26.497** | 31.166 | 55.709 | 56.647 |

## 2. Compile time (median, ms)

NURL's compile is two stages: `nurlc.exe` emits LLVM IR, then `clang`
lowers and links it against `stdlib\runtime.o`. **NURL total** is the
number comparable to the C and Rust columns. The floor row is what each
toolchain costs for a program that does nothing — for NURL that is
dominated by the link every NURL binary pays for, so subtract it to read
the marginal cost of the benchmark itself. Node and Python have no column
here: they compile at run time, inside their own cells above.

| Benchmark | NURL `nurlc` | NURL `clang` | **NURL total** | C `clang` | Rust `rustc` |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _19.296_ | _140.689_ | _**159.985**_ | _134.885_ | _150.452_ |
| `lcg` | 20.275 | 147.284 | **167.559** | 142.459 | 161.837 |
| `affine_mix` | 19.871 | 137.448 | **157.319** | 148.864 | 165.992 |
| `packet_classifier` | 19.912 | 132.855 | **152.767** | 143.176 | 163.810 |
| `ring_write` | 19.853 | 142.181 | **162.034** | 146.878 | 163.316 |
| `histogram_bins` | 19.582 | 139.547 | **159.129** | 159.375 | 165.832 |
| `prefix_scan` | 20.905 | 140.252 | **161.157** | 146.447 | 167.459 |
| `binary_search` | 20.524 | 136.254 | **156.778** | 149.383 | 169.737 |
| `sort_window` | 20.875 | 143.335 | **164.210** | 154.604 | 173.932 |
| `bloom_filter` | 20.333 | 143.749 | **164.082** | 147.674 | 169.643 |
| `hash_join` | 27.745 | 175.182 | **202.927** | 179.524 | 213.555 |
| `sieve` | 20.176 | 152.034 | **172.210** | 159.493 | 173.474 |
| `fib` | 19.631 | 135.299 | **154.930** | 144.115 | 157.994 |
| `collatz` | 19.652 | 145.569 | **165.221** | 146.551 | 160.852 |
| `matmul` | 20.816 | 146.205 | **167.021** | 164.708 | 189.942 |
| `json_parse` | 100.124 | 490.862 | **590.986** | 187.992 | 296.932 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
line. A speed number for a program computing something else is worthless,
so a mismatch drops the row out of the tables above rather than being
reported as a fast cell. Comparison is on the text, with CRLF normalised
to LF — C's and Python's stdio are in text mode on Windows and the NURL
runtime writes bytes, which is a line-ending difference and nothing more.

| Benchmark | Output | Verdict |
|---|---|---|
| `lcg` | `-7585129161289236796` | identical across 5 languages |
| `affine_mix` | `227901546981696845` | identical across 5 languages |
| `packet_classifier` | `4205972061` | identical across 5 languages |
| `ring_write` | `8299504528805184357` | identical across 5 languages |
| `histogram_bins` | `1215643728` | identical across 5 languages |
| `prefix_scan` | `492982549` | identical across 5 languages |
| `binary_search` | `805907445` | identical across 5 languages |
| `sort_window` | `2815490238` | identical across 5 languages |
| `bloom_filter` | `2351703` | identical across 5 languages |
| `hash_join` | `2814341850483607168` | identical across 5 languages |
| `sieve` | `664579` | identical across 5 languages |
| `fib` | `9227465` | identical across 5 languages |
| `collatz` | `350` | identical across 5 languages |
| `matmul` | `393199` | identical across 5 languages |
| `json_parse` | `20` | identical across 5 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, DLL loading and
  page faults rather than the benchmark. The rows worth comparing are the
  ones in the tens of milliseconds and up. The Windows floor is higher
  than the Linux one across the board — loader work, not the language.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Ten of the fifteen benchmarks are defined over 64-bit unsigned integers.
  Python has arbitrary-precision integers and masks; JS has no 64-bit
  integer at all, so those rows use `BigInt` where the algorithm genuinely
  needs 64 bits and Numbers with `Math.imul` where 32 bits suffice. Each
  file says which and why. That gap *is* part of what this table reports.
* `json_parse` is the one row whose gate is "every parser accepted the
  document" rather than a structural checksum: each language uses the
  parser in its own box (Python `json`, Node `JSON.parse`, NURL
  `stdlib/ext/json.nu`), and C and Rust — whose boxes are empty — carry a
  small hand-written recursive-descent parser in the benchmark file.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a laptop that can thermally throttle or drop
  to a power-saving governor mid-suite. Compare deltas between runs on the
  same box, not absolutes across machines — and never across OSes here,
  for the link-line reason at the top of this file.
