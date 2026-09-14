# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-14T23:54:16Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `83966b4d690559b4c4ba2555dd7225403407274b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34910577912 |
| NURL | `v0.65.0-22-g83966b4d` |
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
| _(floor: empty program)_ | _1.249_ | _1.200_ | _1.375_ | _21.467_ | _15.903_ |
| `lcg` | **37.372** | 37.467 | 37.783 | 1867.805 | 5314.144 |
| `packet_classifier` | **52.756** | 52.823 | 52.923 | 159.384 | 4240.025 |
| `ring_write` | 40.654 | **40.536** | 40.912 | 71.214 | 6636.495 |
| `histogram_bins` | 40.561 | 40.787 | **40.436** | 68.069 | 6027.137 |
| `prefix_scan` | 21.370 | 21.238 | **20.819** | 68.313 | 4368.505 |
| `binary_search` | 35.125 | 29.887 | **28.393** | 108.678 | 6534.722 |
| `sort_window` | 35.737 | **34.974** | 36.661 | 183.188 | 10945.281 |
| `bloom_filter` | 13.814 | 14.018 | **13.764** | 2802.743 | 7699.306 |
| `hash_join` | **25.024** | 25.077 | 26.924 | 3443.618 | 8108.254 |
| `sieve` | 32.687 | 34.395 | **32.464** | 84.511 | 3620.105 |
| `fib` | 25.661 | 26.373 | **25.546** | 123.557 | 1176.801 |
| `collatz` | 12.739 | 12.617 | **12.580** | 56.476 | 683.767 |
| `matmul` | **17.005** | 17.293 | 17.229 | 73.192 | 3191.348 |
| `json_parse` | 8.630 | **7.433** | 9.556 | 33.815 | 36.606 |
| `nbody` | 21.788 | 35.337 | **21.171** | 92.997 | 2444.031 |

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
| _(floor: empty program)_ | _2.776_ | _86.910_ | _**89.686**_ | _52.888_ | _72.340_ | _57.073_ |
| `lcg` | 2.963 | 96.509 | **99.472** | 53.787 | 76.460 | 64.383 |
| `packet_classifier` | 3.323 | 98.462 | **101.785** | 54.446 | 81.812 | 67.490 |
| `ring_write` | 4.438 | 97.556 | **101.994** | 54.088 | 78.949 | 67.657 |
| `histogram_bins` | 3.389 | 104.021 | **107.410** | 53.364 | 94.592 | 73.603 |
| `prefix_scan` | 3.424 | 97.623 | **101.047** | 52.289 | 86.200 | 70.385 |
| `binary_search` | 3.861 | 99.538 | **103.399** | 54.490 | 82.680 | 73.149 |
| `sort_window` | 3.840 | 101.077 | **104.917** | 54.816 | 91.728 | 78.543 |
| `bloom_filter` | 4.423 | 107.436 | **111.859** | 56.118 | 89.529 | 79.443 |
| `hash_join` | 8.606 | 233.075 | **241.681** | 58.891 | 191.364 | 117.753 |
| `sieve` | 3.500 | 95.847 | **99.347** | 52.695 | 86.606 | 82.217 |
| `fib` | 3.026 | 95.408 | **98.434** | 52.922 | 77.866 | 63.652 |
| `collatz` | 3.615 | 99.203 | **102.818** | 54.140 | 78.933 | 66.068 |
| `matmul` | 3.891 | 96.148 | **100.039** | 53.104 | 92.697 | 90.002 |
| `json_parse` | 98.733 | 421.864 | **520.597** | 151.126 | 142.578 | 178.254 |
| `nbody` | 5.869 | 116.430 | **122.299** | 56.822 | 113.802 | 100.059 |

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
