# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T19:43:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `89b5358941345b12ce864294869a151ed638095f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40012927414 |
| NURL | `v0.77.2-14-g89b53589` |
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
| _(floor: empty program)_ | _1.240_ | _1.225_ | _1.382_ | _19.026_ | _13.507_ |
| `lcg` | **29.680** | 29.816 | 32.315 | 1133.722 | 3069.971 |
| `packet_classifier` | **42.825** | 43.691 | 42.979 | 133.463 | 2661.674 |
| `ring_write` | **29.898** | 29.903 | 30.218 | 51.958 | 3755.506 |
| `histogram_bins` | 30.187 | **30.165** | 30.228 | 52.448 | 3470.314 |
| `prefix_scan` | **16.367** | 16.484 | 16.637 | 50.759 | 2628.033 |
| `binary_search` | 14.965 | **14.964** | 15.641 | 71.129 | 3530.606 |
| `sort_window` | 20.967 | **20.814** | 21.217 | 138.784 | 6675.522 |
| `bloom_filter` | **9.118** | 9.248 | 9.466 | 1710.034 | 4493.178 |
| `hash_join` | **16.793** | 17.676 | 18.697 | 2026.385 | 4665.190 |
| `sieve` | 12.788 | **12.419** | 12.512 | 46.977 | 1927.532 |
| `fib` | **20.011** | 20.174 | 20.144 | 80.505 | 701.538 |
| `collatz` | **9.658** | 9.727 | 10.037 | 39.745 | 429.312 |
| `matmul` | 20.998 | 21.090 | **20.765** | 52.182 | 1816.816 |
| `json_parse` | **5.228** | 5.552 | 7.289 | 26.171 | 26.078 |
| `nbody` | **17.210** | 25.326 | 17.554 | 65.796 | 1545.224 |
| `chacha20` | **7.336** | 21.014 | 20.319 | n/a | n/a |
| `poly1305` | **15.464** | 27.311 | 16.164 | n/a | n/a |
| `blake2b` | **27.102** | 43.145 | 48.960 | n/a | n/a |
| `sha512` | **30.775** | 34.243 | 33.115 | n/a | n/a |
| `x25519` | **28.212** | 30.978 | 31.605 | n/a | n/a |

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
| _(floor: empty program)_ | _3.749_ | _95.047_ | _**98.796**_ | _53.229_ | _71.183_ | _45.004_ |
| `lcg` | 3.641 | 98.267 | **101.908** | 50.603 | 75.531 | 48.631 |
| `packet_classifier` | 3.593 | 97.077 | **100.670** | 49.389 | 78.162 | 48.335 |
| `ring_write` | 9.898 | 99.749 | **109.647** | 58.033 | 79.946 | 53.854 |
| `histogram_bins` | 10.009 | 107.917 | **117.926** | 59.657 | 90.543 | 56.312 |
| `prefix_scan` | 9.922 | 102.582 | **112.504** | 58.549 | 80.420 | 51.263 |
| `binary_search` | 10.100 | 104.554 | **114.654** | 59.736 | 83.783 | 55.668 |
| `sort_window` | 10.208 | 104.422 | **114.630** | 60.277 | 85.867 | 56.991 |
| `bloom_filter` | 10.604 | 106.599 | **117.203** | 59.985 | 87.301 | 65.985 |
| `hash_join` | 12.626 | 185.175 | **197.801** | 61.319 | 146.079 | 81.328 |
| `sieve` | 10.051 | 105.117 | **115.168** | 59.818 | 87.199 | 59.920 |
| `fib` | 3.948 | 101.223 | **105.171** | 51.280 | 79.084 | 49.805 |
| `collatz` | 4.164 | 105.325 | **109.489** | 55.384 | 86.126 | 54.440 |
| `matmul` | 10.904 | 102.876 | **113.780** | 59.050 | 86.965 | 63.585 |
| `json_parse` | 31.538 | 334.802 | **366.340** | 81.323 | 127.163 | 126.629 |
| `nbody` | 11.281 | 109.615 | **120.896** | 62.188 | 103.635 | 77.986 |
| `chacha20` | 30.875 | 525.776 | **556.651** | 78.870 | 111.952 | 90.052 |
| `poly1305` | 22.833 | 211.166 | **233.999** | 71.141 | 110.226 | 92.332 |
| `blake2b` | 25.642 | 263.708 | **289.350** | 74.356 | 115.015 | 91.016 |
| `sha512` | 25.322 | 316.967 | **342.289** | 73.180 | 109.896 | 79.775 |
| `x25519` | 23.975 | 574.463 | **598.438** | 79.008 | 771.043 | 330.492 |

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
