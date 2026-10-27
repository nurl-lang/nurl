# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T05:52:56Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373444 KiB |
| Commit | `bae01bf283cb6fd386de094818c242b7abeed163` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40457179361 |
| NURL | `v0.78.0-41-gbae01bf2` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.3 |
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
| Workload scale | ×1 — the published contract (`--scale N` / `BENCH_SCALE=N` multiplies it) |

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so a row's cells are timings of the
same computation. **Bold** is the fastest cell in the row; `n/a` is a
language the row is not implemented in (bench/manifest.tsv).

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.471_ | _1.430_ | _1.642_ | _24.426_ | _20.905_ |
| `lcg` | 39.443 | **39.244** | 39.336 | 1892.852 | 5095.325 |
| `packet_classifier` | 56.349 | **56.289** | 56.589 | 162.935 | 4303.388 |
| `ring_write` | 42.359 | **42.155** | 42.466 | 66.856 | 6450.009 |
| `histogram_bins` | 40.665 | **40.634** | 40.855 | 70.192 | 6286.396 |
| `prefix_scan` | **21.688** | 21.981 | 22.027 | 68.083 | 5055.535 |
| `binary_search` | 38.452 | **38.368** | 41.099 | 108.470 | 6572.350 |
| `sort_window` | 26.566 | **26.518** | 26.607 | 197.033 | 12723.504 |
| `bloom_filter` | **15.394** | 18.126 | 18.662 | 2841.329 | 7417.959 |
| `hash_join` | **27.072** | 28.108 | 29.503 | 3450.887 | 8340.146 |
| `sieve` | **19.890** | 20.025 | 20.572 | 67.720 | 3308.895 |
| `fib` | **29.667** | 29.914 | 30.122 | 133.745 | 1386.471 |
| `collatz` | 12.431 | **12.145** | 12.872 | 50.519 | 767.052 |
| `matmul` | 34.322 | **33.298** | 33.974 | 78.154 | 3211.047 |
| `json_parse` | **8.633** | 9.076 | 12.278 | 40.091 | 42.107 |
| `nbody` | **25.462** | 39.778 | 25.532 | 99.971 | 3179.472 |
| `chacha20` | **8.289** | 42.384 | 33.927 | n/a | n/a |
| `poly1305` | **11.950** | 31.989 | 21.058 | n/a | n/a |
| `blake2b` | **43.648** | 64.960 | 69.283 | n/a | n/a |
| `sha512` | **47.230** | 50.816 | 49.584 | n/a | n/a |
| `x25519` | **44.205** | 48.678 | 49.227 | n/a | n/a |

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
| _(floor: empty program)_ | _4.717_ | _116.630_ | _**121.347**_ | _64.506_ | _85.632_ | _56.372_ |
| `lcg` | 4.565 | 131.281 | **135.846** | 63.523 | 88.594 | 60.775 |
| `packet_classifier` | 4.723 | 127.071 | **131.794** | 63.657 | 90.731 | 58.061 |
| `ring_write` | 15.879 | 136.094 | **151.973** | 74.359 | 95.325 | 63.538 |
| `histogram_bins` | 15.515 | 132.298 | **147.813** | 74.427 | 117.472 | 67.088 |
| `prefix_scan` | 15.624 | 132.878 | **148.502** | 75.286 | 96.980 | 65.523 |
| `binary_search` | 15.921 | 130.835 | **146.756** | 75.045 | 97.578 | 65.094 |
| `sort_window` | 16.199 | 130.187 | **146.386** | 74.820 | 104.104 | 67.720 |
| `bloom_filter` | 16.619 | 140.167 | **156.786** | 75.630 | 102.148 | 65.028 |
| `hash_join` | 20.240 | 272.689 | **292.929** | 79.351 | 220.342 | 111.542 |
| `sieve` | 16.393 | 131.815 | **148.208** | 77.414 | 108.038 | 69.913 |
| `fib` | 4.793 | 130.563 | **135.356** | 64.600 | 95.320 | 59.020 |
| `collatz` | 4.855 | 133.962 | **138.817** | 67.238 | 91.026 | 60.652 |
| `matmul` | 17.854 | 133.504 | **151.358** | 78.218 | 108.466 | 84.363 |
| `json_parse` | 50.567 | 505.365 | **555.932** | 107.769 | 177.710 | 176.159 |
| `nbody` | 20.069 | 151.461 | **171.530** | 83.346 | 135.172 | 97.424 |
| `chacha20` | 57.652 | 849.352 | **907.004** | 119.123 | 143.707 | 107.458 |
| `poly1305` | 45.452 | 530.785 | **576.237** | 107.044 | 144.785 | 123.081 |
| `blake2b` | 39.932 | 388.154 | **428.086** | 104.597 | 148.311 | 117.162 |
| `sha512` | 39.469 | 489.736 | **529.205** | 101.348 | 151.523 | 106.363 |
| `x25519` | 39.709 | 841.509 | **881.218** | 99.652 | 1231.816 | 501.256 |

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
