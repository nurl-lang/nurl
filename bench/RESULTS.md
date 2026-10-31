# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T14:24:45Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `4781794493963f1784b96706ff656e24462db7af` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41209056453 |
| NURL | `v0.82.0-49-g47817944` |
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
| _(floor: empty program)_ | _2.670_ | _2.593_ | _2.732_ | _18.456_ | _10.239_ |
| `lcg` | **31.713** | 31.818 | 31.867 | 1108.431 | 2779.284 |
| `packet_classifier` | **42.446** | 43.297 | 44.050 | 130.142 | 2415.404 |
| `ring_write` | **30.958** | 31.751 | 32.011 | 53.203 | 3402.575 |
| `histogram_bins` | 31.653 | **31.596** | 31.683 | 52.285 | 3057.374 |
| `prefix_scan` | 17.754 | 17.745 | **17.611** | 47.227 | 2214.257 |
| `binary_search` | 17.145 | **16.446** | 17.236 | 73.700 | 3849.852 |
| `sort_window` | 22.383 | **21.677** | 22.514 | 141.281 | 6661.687 |
| `bloom_filter` | 10.896 | **10.643** | 10.945 | 1644.165 | 4352.862 |
| `hash_join` | 17.750 | **17.742** | 19.889 | 1959.974 | 4289.001 |
| `sieve` | **17.056** | 17.424 | 17.308 | 51.607 | 1816.481 |
| `fib` | 21.620 | **21.071** | 21.113 | 78.656 | 566.637 |
| `collatz` | 11.196 | **11.136** | 11.223 | 39.623 | 382.389 |
| `matmul` | 22.645 | 22.816 | **22.634** | 53.441 | 1648.974 |
| `json_parse` | **6.978** | 8.849 | 12.384 | 27.456 | 26.949 |
| `nbody` | **18.443** | 28.019 | 19.923 | 63.534 | 1442.116 |
| `chacha20` | **7.211** | 21.943 | 21.618 | n/a | n/a |
| `poly1305` | **10.450** | 30.069 | 17.604 | n/a | n/a |
| `blake2b` | **28.683** | 45.979 | 50.851 | n/a | n/a |
| `sha512` | 32.870 | **32.563** | 34.274 | n/a | n/a |
| `x25519` | **21.776** | 33.497 | 33.831 | n/a | n/a |

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
| _(floor: empty program)_ | _5.113_ | _88.636_ | _**93.749**_ | _48.194_ | _63.346_ | _50.159_ |
| `lcg` | 5.296 | 94.122 | **99.418** | 48.003 | 71.190 | 56.081 |
| `packet_classifier` | 5.319 | 93.108 | **98.427** | 48.376 | 72.568 | 60.012 |
| `ring_write` | 11.699 | 98.212 | **109.911** | 55.360 | 71.935 | 61.029 |
| `histogram_bins` | 11.779 | 102.148 | **113.927** | 56.486 | 102.952 | 66.823 |
| `prefix_scan` | 11.728 | 103.120 | **114.848** | 57.041 | 78.213 | 64.142 |
| `binary_search` | 11.894 | 100.858 | **112.752** | 57.212 | 77.194 | 63.773 |
| `sort_window` | 12.239 | 102.833 | **115.072** | 57.382 | 80.412 | 67.453 |
| `bloom_filter` | 12.108 | 102.403 | **114.511** | 60.075 | 81.074 | 65.566 |
| `hash_join` | 14.404 | 174.709 | **189.113** | 59.933 | 146.803 | 99.899 |
| `sieve` | 12.576 | 103.790 | **116.366** | 58.597 | 86.692 | 70.226 |
| `fib` | 5.568 | 97.936 | **103.504** | 51.223 | 72.347 | 59.680 |
| `collatz` | 5.655 | 99.582 | **105.237** | 50.361 | 73.505 | 60.318 |
| `matmul` | 12.241 | 102.272 | **114.513** | 57.883 | 81.875 | 76.765 |
| `json_parse` | 32.000 | 295.219 | **327.219** | 80.447 | 119.380 | 137.837 |
| `nbody` | 13.244 | 109.413 | **122.657** | 59.462 | 96.903 | 89.034 |
| `chacha20` | 35.784 | 516.330 | **552.114** | 82.615 | 103.990 | 97.076 |
| `poly1305` | 29.071 | 231.157 | **260.228** | 75.490 | 106.940 | 102.913 |
| `blake2b` | 26.066 | 230.283 | **256.349** | 74.852 | 113.402 | 105.397 |
| `sha512` | 25.607 | 288.336 | **313.943** | 71.862 | 102.629 | 92.792 |
| `x25519` | 33.276 | 913.660 | **946.936** | 80.092 | 732.041 | 341.177 |

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
