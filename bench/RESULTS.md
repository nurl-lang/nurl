# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T10:54:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `0e5a95805d35e679e7cddf3159552a520391a37c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41193662480 |
| NURL | `v0.82.0-28-g0e5a9580` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.1 |
| Python | Python 3.14.4 |

| Setting | Value |
|---|---|
| NURL flags | `nurlc` → LLVM IR; `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` (ThinLTO backend at O3 — the standard `nurl.sh` release pipeline) |
| C flags | `clang -O2 -flto=thin -c`; link `clang -O2 -flto=thin -Wl,-plugin-opt,O3` — the identical pipeline, so neither column gets a backend the other lacks |
| Rust flags | `rustc -C opt-level=3` — rustc has no prelink/backend split; opt-level 3 is the `cargo build --release` default |
| Node / Python | `node` / `python3`, no flags |
| Timed runs per cell | up to 5, adaptive: as many as fit in 8000 ms |
| Timed compiles per cell | 3 (median) |
| Per-run timeout | 300 s |
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _3.697_ | _3.613_ | _3.814_ | _29.668_ | _16.548_ |
| `lcg` | **41.954** | 42.092 | 42.275 | 1798.370 | 4919.044 |
| `packet_classifier` | 59.227 | **59.131** | 59.366 | 171.496 | 4105.573 |
| `ring_write` | 45.290 | **45.100** | 45.636 | 75.107 | 6433.469 |
| `histogram_bins` | **42.704** | 43.790 | 43.971 | 75.878 | 5759.774 |
| `prefix_scan` | **24.725** | 24.737 | 25.115 | 72.707 | 4133.837 |
| `binary_search` | 42.649 | **41.166** | 44.207 | 114.175 | 5929.601 |
| `sort_window` | 29.681 | **29.559** | 29.770 | 203.286 | 11958.971 |
| `bloom_filter` | **19.199** | 20.639 | 20.881 | 2937.436 | 7132.403 |
| `hash_join` | **29.520** | 29.722 | 32.294 | 3379.998 | 7725.477 |
| `sieve` | 27.825 | **27.784** | 28.572 | 77.113 | 3238.641 |
| `fib` | **27.829** | 32.495 | 33.074 | 140.176 | 1117.425 |
| `collatz` | 14.794 | **14.676** | 14.942 | 57.970 | 695.696 |
| `matmul` | **36.827** | 37.211 | 37.569 | 79.638 | 3061.615 |
| `json_parse` | **11.670** | 13.915 | 19.959 | 47.652 | 39.800 |
| `nbody` | **26.800** | 42.703 | 28.405 | 108.963 | 2881.738 |
| `chacha20` | **10.353** | 43.779 | 36.246 | n/a | n/a |
| `poly1305` | **13.797** | 34.215 | 23.755 | n/a | n/a |
| `blake2b` | **46.718** | 67.493 | 72.023 | n/a | n/a |
| `sha512` | 50.429 | **50.278** | 52.250 | n/a | n/a |
| `x25519` | **34.836** | 51.984 | 52.493 | n/a | n/a |

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
| _(floor: empty program)_ | _7.205_ | _135.185_ | _**142.390**_ | _74.493_ | _92.939_ | _73.404_ |
| `lcg` | 7.586 | 146.732 | **154.318** | 72.628 | 104.888 | 79.927 |
| `packet_classifier` | 7.436 | 146.630 | **154.066** | 73.224 | 107.550 | 82.384 |
| `ring_write` | 17.844 | 150.954 | **168.798** | 87.395 | 114.379 | 95.709 |
| `histogram_bins` | 17.742 | 152.346 | **170.088** | 84.618 | 149.850 | 88.846 |
| `prefix_scan` | 17.962 | 148.148 | **166.110** | 81.563 | 111.588 | 83.319 |
| `binary_search` | 18.263 | 148.580 | **166.843** | 84.055 | 109.229 | 87.943 |
| `sort_window` | 18.538 | 155.323 | **173.861** | 86.738 | 122.776 | 91.964 |
| `bloom_filter` | 18.646 | 150.069 | **168.715** | 83.215 | 114.280 | 85.112 |
| `hash_join` | 21.442 | 282.056 | **303.498** | 84.632 | 230.920 | 131.526 |
| `sieve` | 17.852 | 146.967 | **164.819** | 82.688 | 120.321 | 91.517 |
| `fib` | 7.466 | 143.956 | **151.422** | 73.135 | 104.969 | 78.970 |
| `collatz` | 7.614 | 148.255 | **155.869** | 72.070 | 109.331 | 79.635 |
| `matmul` | 18.208 | 148.410 | **166.618** | 82.213 | 121.689 | 105.513 |
| `json_parse` | 52.242 | 487.135 | **539.377** | 121.193 | 179.064 | 205.010 |
| `nbody` | 20.225 | 162.337 | **182.562** | 90.727 | 149.110 | 122.129 |
| `chacha20` | 60.925 | 794.701 | **855.626** | 126.612 | 160.560 | 133.514 |
| `poly1305` | 47.848 | 534.096 | **581.944** | 112.877 | 159.707 | 145.248 |
| `blake2b` | 39.848 | 352.949 | **392.797** | 104.393 | 163.988 | 140.184 |
| `sha512` | 41.159 | 478.992 | **520.151** | 106.775 | 154.386 | 126.827 |
| `x25519` | 55.407 | 1587.933 | **1643.340** | 121.958 | 1282.266 | 527.205 |

## 3. Correctness gate

Each row is timed only when all of its implementations print the same
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
| `chacha20` | `3720502699256473595` | identical across 3 languages |
| `poly1305` | `2498856793803813402` | identical across 3 languages |
| `blake2b` | `8590291023788228918` | identical across 3 languages |
| `sha512` | `7091519178481951668` | identical across 3 languages |
| `x25519` | `6127485567278337128` | identical across 3 languages |

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the original fifteen benchmarks are defined over 64-bit unsigned integers.
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
* `chacha20`, `poly1305`, `blake2b`, `sha512` and `x25519` are NURL / C /
  Rust only. Their NURL file is a driver around the standard library's own
  implementation (stdlib/std/chacha20poly1305.nu, hash_blake2b.nu,
  hash_sha512.nu, x25519.nu) — the row measures the stdlib a NURL program
  actually gets. C and Rust, whose standard libraries have none of the
  five, carry the same formulation written out by hand: Poly1305 at
  radix 2^64 and the donna-c64 X25519 field at radix 2^51, both with
  native 128-bit products. ChaCha20 is the one deliberate difference: C
  and Rust run the scalar RFC rounds, while the stdlib runs it on `v128`
  lanes (`v256` lanes in its x86-64-v3 clone). Each source names its
  RFC/FIPS test vector; x25519 at x1 reproduces RFC 7748's 1000-iteration
  value.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
