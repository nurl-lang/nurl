# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T12:48:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `40e0e201328638f717fb959441b1d5b97fcaabd4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41202162912 |
| NURL | `v0.82.0-41-g40e0e201` |
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
| _(floor: empty program)_ | _3.284_ | _3.315_ | _3.542_ | _27.026_ | _14.873_ |
| `lcg` | 41.240 | **41.075** | 41.209 | 1791.114 | 4942.860 |
| `packet_classifier` | 58.358 | **58.159** | 58.499 | 167.533 | 4079.581 |
| `ring_write` | 44.422 | **44.282** | 44.444 | 71.123 | 6196.978 |
| `histogram_bins` | **41.634** | 42.720 | 42.973 | 70.202 | 5576.827 |
| `prefix_scan` | 23.750 | **23.588** | 24.034 | 66.940 | 4191.994 |
| `binary_search` | 41.563 | **40.177** | 42.866 | 109.587 | 6023.100 |
| `sort_window` | 28.821 | **28.612** | 28.814 | 198.708 | 11882.938 |
| `bloom_filter` | **18.671** | 19.734 | 20.289 | 2844.797 | 7036.410 |
| `hash_join` | 28.831 | **28.690** | 31.157 | 3363.013 | 7782.681 |
| `sieve` | 25.670 | **25.532** | 25.545 | 73.596 | 3065.245 |
| `fib` | **27.257** | 31.850 | 32.098 | 136.120 | 1112.323 |
| `collatz` | 14.192 | **14.108** | 14.331 | 53.777 | 703.278 |
| `matmul` | 35.549 | **35.379** | 35.706 | 75.323 | 3072.053 |
| `json_parse` | **10.438** | 13.112 | 18.374 | 39.411 | 36.233 |
| `nbody` | **26.108** | 41.637 | 27.286 | 104.073 | 3041.340 |
| `chacha20` | **9.538** | 44.281 | 35.708 | n/a | n/a |
| `poly1305` | **13.553** | 33.858 | 23.050 | n/a | n/a |
| `blake2b` | **45.634** | 66.661 | 71.184 | n/a | n/a |
| `sha512` | **49.248** | 49.378 | 51.359 | n/a | n/a |
| `x25519` | **33.427** | 51.054 | 51.537 | n/a | n/a |

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
| _(floor: empty program)_ | _6.639_ | _125.210_ | _**131.849**_ | _63.239_ | _80.411_ | _63.308_ |
| `lcg` | 6.667 | 129.222 | **135.889** | 62.852 | 89.422 | 71.673 |
| `packet_classifier` | 6.842 | 129.198 | **136.040** | 62.890 | 90.539 | 72.866 |
| `ring_write` | 16.706 | 135.312 | **152.018** | 75.037 | 94.476 | 75.331 |
| `histogram_bins` | 16.824 | 135.951 | **152.775** | 73.892 | 136.731 | 83.721 |
| `prefix_scan` | 16.924 | 134.153 | **151.077** | 73.505 | 97.866 | 76.946 |
| `binary_search` | 16.993 | 134.581 | **151.574** | 73.261 | 94.157 | 78.079 |
| `sort_window` | 16.988 | 135.495 | **152.483** | 73.826 | 103.584 | 85.492 |
| `bloom_filter` | 17.524 | 136.448 | **153.972** | 73.768 | 103.238 | 79.584 |
| `hash_join` | 20.774 | 267.105 | **287.879** | 77.115 | 216.050 | 125.376 |
| `sieve` | 16.917 | 134.736 | **151.653** | 74.343 | 105.708 | 85.038 |
| `fib` | 6.895 | 129.496 | **136.391** | 63.877 | 90.864 | 72.340 |
| `collatz` | 7.037 | 133.495 | **140.532** | 64.880 | 92.498 | 73.518 |
| `matmul` | 17.315 | 133.559 | **150.874** | 72.784 | 107.164 | 95.663 |
| `json_parse` | 50.618 | 457.011 | **507.629** | 109.694 | 160.656 | 177.698 |
| `nbody` | 19.151 | 161.761 | **180.912** | 83.453 | 136.197 | 111.718 |
| `chacha20` | 59.332 | 837.226 | **896.558** | 118.401 | 145.402 | 123.978 |
| `poly1305` | 47.007 | 349.014 | **396.021** | 106.157 | 149.402 | 138.601 |
| `blake2b` | 39.785 | 336.568 | **376.353** | 98.700 | 149.107 | 132.577 |
| `sha512` | 40.020 | 454.325 | **494.345** | 98.116 | 138.980 | 118.511 |
| `x25519` | 54.674 | 1536.880 | **1591.554** | 112.075 | 1232.074 | 509.406 |

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
