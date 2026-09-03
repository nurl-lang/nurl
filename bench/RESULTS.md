# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-03T03:49:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `f62e5ab2463c15685e9e9a1499138d92d11a9a05` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33712420729 |
| NURL | `v0.58.0-19-gf62e5ab2` |
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
| _(floor: empty program)_ | _1.452_ | _1.418_ | _1.631_ | _22.521_ | _16.783_ |
| `lcg` | **38.958** | 39.023 | 39.138 | 2047.608 | 5548.357 |
| `packet_classifier` | **56.099** | 56.113 | 56.361 | 160.092 | 4637.639 |
| `ring_write` | **42.096** | 42.097 | 42.368 | 65.261 | 6834.273 |
| `histogram_bins` | **39.448** | 40.534 | 39.619 | 64.039 | 6192.163 |
| `prefix_scan` | **21.579** | 21.611 | 21.718 | 64.503 | 4538.031 |
| `binary_search` | 39.399 | 38.200 | **36.878** | 105.011 | 6262.703 |
| `sort_window` | **26.543** | 26.557 | 26.757 | 196.269 | 11977.645 |
| `bloom_filter` | 17.835 | **17.795** | 18.266 | 2835.305 | 7543.734 |
| `hash_join` | **26.756** | 27.945 | 29.322 | 3527.936 | 8353.408 |
| `sieve` | 18.013 | **17.618** | 17.675 | 63.967 | 3290.135 |
| `fib` | **25.065** | 29.702 | 25.184 | 130.126 | 1353.170 |
| `collatz` | 12.225 | **12.187** | 12.319 | 48.028 | 744.252 |
| `matmul` | **33.205** | 33.303 | 33.581 | 75.580 | 3205.329 |
| `json_parse` | 8.953 | **8.485** | 11.605 | 34.826 | 37.117 |
| `nbody` | 25.101 | 39.741 | **24.059** | 97.989 | 3068.443 |

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
| _(floor: empty program)_ | _2.629_ | _93.368_ | _**95.997**_ | _57.170_ | _75.232_ | _58.802_ |
| `lcg` | 2.739 | 102.272 | **105.011** | 56.285 | 85.460 | 66.051 |
| `packet_classifier` | 2.867 | 102.035 | **104.902** | 56.366 | 86.737 | 66.265 |
| `ring_write` | 2.955 | 104.182 | **107.137** | 56.900 | 89.076 | 69.349 |
| `histogram_bins` | 3.042 | 114.563 | **117.605** | 57.710 | 105.281 | 76.462 |
| `prefix_scan` | 3.065 | 105.838 | **108.903** | 57.075 | 93.662 | 71.593 |
| `binary_search` | 3.227 | 105.114 | **108.341** | 57.429 | 89.691 | 73.432 |
| `sort_window` | 3.271 | 108.293 | **111.564** | 57.915 | 99.836 | 78.238 |
| `bloom_filter` | 3.516 | 108.867 | **112.383** | 58.125 | 97.815 | 74.237 |
| `hash_join` | 6.049 | 254.175 | **260.224** | 61.071 | 214.242 | 121.909 |
| `sieve` | 3.084 | 103.862 | **106.946** | 57.585 | 98.792 | 79.843 |
| `fib` | 2.758 | 103.190 | **105.948** | 57.058 | 85.548 | 66.689 |
| `collatz` | 3.006 | 106.619 | **109.625** | 57.949 | 88.008 | 69.092 |
| `matmul` | 3.341 | 104.888 | **108.229** | 58.119 | 103.588 | 92.065 |
| `json_parse` | 57.083 | 449.332 | **506.415** | 112.653 | 156.029 | 173.228 |
| `nbody` | 4.725 | 124.216 | **128.941** | 58.789 | 124.512 | 99.490 |

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
