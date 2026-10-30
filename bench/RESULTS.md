# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T03:24:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `c8bcce0640979e69748462a9e382f3721a7c9e83` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40996538821 |
| NURL | `v0.80.0-100-gc8bcce06` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.4 |
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
| _(floor: empty program)_ | _1.357_ | _1.314_ | _1.498_ | _22.126_ | _15.985_ |
| `lcg` | 34.485 | **34.469** | 34.626 | 1444.308 | 4110.197 |
| `packet_classifier` | **49.474** | 49.504 | 49.643 | 126.777 | 3585.312 |
| `ring_write` | 37.153 | **37.121** | 37.344 | 61.263 | 4984.501 |
| `histogram_bins` | **34.827** | 34.870 | 35.018 | 60.448 | 5108.239 |
| `prefix_scan` | 19.152 | **19.108** | 19.407 | 59.723 | 3614.386 |
| `binary_search` | 32.614 | **28.447** | 33.652 | 88.651 | 6570.202 |
| `sort_window` | 23.514 | **23.508** | 23.660 | 132.501 | 8651.580 |
| `bloom_filter` | **13.562** | 14.573 | 16.193 | 2177.062 | 6327.181 |
| `hash_join` | **21.800** | 22.912 | 23.681 | 2698.301 | 6400.823 |
| `sieve` | 20.636 | 19.762 | **19.641** | 62.308 | 2818.256 |
| `fib` | **21.834** | 25.924 | 26.130 | 112.989 | 1001.640 |
| `collatz` | 10.852 | **10.840** | 11.090 | 44.115 | 584.321 |
| `matmul` | **35.237** | 35.745 | 35.262 | 68.644 | 2678.902 |
| `json_parse` | **6.422** | 7.057 | 9.695 | 34.334 | 33.572 |
| `nbody` | 21.107 | 35.151 | **21.092** | 77.425 | 2544.011 |
| `chacha20` | **6.906** | 36.039 | 27.895 | n/a | n/a |
| `poly1305` | **10.193** | 31.483 | 18.768 | n/a | n/a |
| `blake2b` | **38.553** | 55.804 | 60.759 | n/a | n/a |
| `sha512` | **38.877** | 40.425 | 42.538 | n/a | n/a |
| `x25519` | **27.819** | 42.302 | 44.299 | n/a | n/a |

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
| _(floor: empty program)_ | _4.400_ | _107.890_ | _**112.290**_ | _60.303_ | _79.717_ | _60.017_ |
| `lcg` | 4.330 | 118.167 | **122.497** | 60.674 | 88.428 | 65.577 |
| `packet_classifier` | 4.350 | 118.258 | **122.608** | 60.701 | 87.634 | 63.957 |
| `ring_write` | 13.540 | 119.370 | **132.910** | 68.950 | 88.974 | 68.161 |
| `histogram_bins` | 13.567 | 118.026 | **131.593** | 68.617 | 101.519 | 72.627 |
| `prefix_scan` | 13.226 | 117.786 | **131.012** | 67.998 | 92.486 | 68.881 |
| `binary_search` | 13.594 | 118.735 | **132.329** | 67.885 | 90.715 | 71.337 |
| `sort_window` | 13.777 | 120.248 | **134.025** | 68.558 | 98.118 | 76.001 |
| `bloom_filter` | 14.019 | 121.301 | **135.320** | 69.148 | 96.077 | 72.069 |
| `hash_join` | 16.559 | 214.150 | **230.709** | 69.749 | 181.876 | 108.463 |
| `sieve` | 13.905 | 121.415 | **135.320** | 70.055 | 98.790 | 79.806 |
| `fib` | 4.486 | 120.477 | **124.963** | 61.662 | 88.674 | 65.549 |
| `collatz` | 4.847 | 123.093 | **127.940** | 62.849 | 96.926 | 66.514 |
| `matmul` | 15.222 | 122.990 | **138.212** | 71.082 | 101.958 | 86.656 |
| `json_parse` | 41.970 | 381.008 | **422.978** | 99.506 | 142.099 | 155.052 |
| `nbody` | 15.924 | 126.255 | **142.179** | 71.772 | 117.939 | 100.008 |
| `chacha20` | 46.610 | 601.814 | **648.424** | 103.775 | 125.686 | 106.929 |
| `poly1305` | 35.842 | 413.205 | **449.047** | 94.259 | 127.271 | 120.080 |
| `blake2b` | 32.853 | 303.293 | **336.146** | 89.205 | 131.668 | 117.394 |
| `sha512` | 32.689 | 375.032 | **407.721** | 88.150 | 125.668 | 105.236 |
| `x25519` | 43.340 | 1001.536 | **1044.876** | 99.531 | 957.385 | 417.953 |

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
