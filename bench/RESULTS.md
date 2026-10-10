# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-10T13:43:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3483311b866fed85b827965075f43e8ced8419be` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38056462450 |
| NURL | `v0.71.0-27-g3483311b` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
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
| _(floor: empty program)_ | _1.433_ | _1.409_ | _1.587_ | _22.971_ | _17.257_ |
| `lcg` | 38.966 | **38.934** | 39.187 | 1912.850 | 5061.536 |
| `packet_classifier` | **56.080** | 56.152 | 56.333 | 160.691 | 4564.219 |
| `ring_write` | **42.071** | 42.135 | 42.341 | 64.793 | 6408.633 |
| `histogram_bins` | **39.658** | 40.693 | 40.853 | 67.014 | 6004.131 |
| `prefix_scan` | **21.666** | 21.674 | 21.889 | 65.384 | 4699.143 |
| `binary_search` | 39.364 | **38.109** | 40.828 | 105.231 | 6636.303 |
| `sort_window` | **26.503** | 26.551 | 26.739 | 196.044 | 11582.382 |
| `bloom_filter` | **15.447** | 17.757 | 18.249 | 2821.842 | 8127.363 |
| `hash_join` | **26.385** | 27.767 | 28.971 | 3402.868 | 8496.835 |
| `sieve` | 20.188 | **19.821** | 19.858 | 65.320 | 3424.567 |
| `fib` | **24.924** | 29.734 | 29.866 | 130.397 | 1365.648 |
| `collatz` | 12.247 | **12.083** | 12.425 | 47.672 | 745.365 |
| `matmul` | 33.442 | **33.240** | 33.439 | 75.378 | 3343.350 |
| `json_parse` | **8.379** | 8.552 | 11.760 | 36.476 | 38.257 |
| `nbody` | **25.129** | 39.659 | 25.369 | 99.770 | 3108.154 |
| `chacha20` | **7.509** | 41.982 | 33.501 | n/a | n/a |
| `poly1305` | 23.379 | 31.712 | **21.043** | n/a | n/a |
| `blake2b` | **43.660** | 64.948 | 68.842 | n/a | n/a |
| `sha512` | **47.261** | 50.481 | 49.476 | n/a | n/a |
| `x25519` | **44.340** | 48.509 | 49.144 | n/a | n/a |

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
| _(floor: empty program)_ | _3.661_ | _97.865_ | _**101.526**_ | _60.415_ | _78.407_ | _58.956_ |
| `lcg` | 3.844 | 109.846 | **113.690** | 59.138 | 86.881 | 66.761 |
| `packet_classifier` | 3.900 | 109.635 | **113.535** | 59.302 | 87.388 | 65.917 |
| `ring_write` | 4.167 | 112.168 | **116.335** | 59.586 | 89.146 | 67.151 |
| `histogram_bins` | 4.334 | 120.213 | **124.547** | 60.082 | 106.209 | 75.032 |
| `prefix_scan` | 4.358 | 112.793 | **117.151** | 61.188 | 96.120 | 70.713 |
| `binary_search` | 4.640 | 114.105 | **118.745** | 62.096 | 92.647 | 72.684 |
| `sort_window` | 4.794 | 114.300 | **119.094** | 61.238 | 100.911 | 77.635 |
| `bloom_filter` | 5.358 | 117.785 | **123.143** | 62.649 | 101.704 | 74.328 |
| `hash_join` | 9.709 | 265.590 | **275.299** | 67.557 | 215.978 | 123.684 |
| `sieve` | 4.599 | 111.186 | **115.785** | 59.785 | 100.222 | 78.030 |
| `fib` | 4.156 | 110.056 | **114.212** | 60.412 | 88.431 | 66.295 |
| `collatz` | 4.222 | 112.455 | **116.677** | 59.635 | 88.731 | 66.649 |
| `matmul` | 6.095 | 112.358 | **118.453** | 61.540 | 103.358 | 87.579 |
| `json_parse` | 50.866 | 480.923 | **531.789** | 109.522 | 158.025 | 167.078 |
| `nbody` | 7.027 | 132.412 | **139.439** | 64.439 | 126.544 | 104.082 |
| `chacha20` | 54.689 | 601.680 | **656.369** | 111.054 | 137.904 | 113.512 |
| `poly1305` | 35.484 | 254.018 | **289.502** | 91.123 | 139.360 | 128.629 |
| `blake2b` | 36.846 | 354.986 | **391.832** | 92.894 | 143.227 | 123.567 |
| `sha512` | 37.301 | 464.765 | **502.066** | 92.774 | 135.765 | 108.564 |
| `x25519` | 46.105 | 713.717 | **759.822** | 102.374 | 1212.132 | 500.741 |

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
