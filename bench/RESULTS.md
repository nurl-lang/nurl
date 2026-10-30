# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T02:47:25Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16366504 KiB |
| Commit | `e985c9e75d812871c644e962b5ecb1ca1f75ea24` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40993160105 |
| NURL | `v0.80.0-97-ge985c9e7` |
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
| _(floor: empty program)_ | _1.315_ | _1.272_ | _1.420_ | _22.266_ | _16.319_ |
| `lcg` | 40.818 | **40.689** | 41.181 | 1519.568 | 4202.049 |
| `packet_classifier` | **69.716** | 70.179 | 70.215 | 171.192 | 3434.077 |
| `ring_write` | 44.684 | **44.519** | 45.162 | 67.246 | 5158.262 |
| `histogram_bins` | 41.925 | **41.737** | 41.893 | 71.028 | 4810.080 |
| `prefix_scan` | 22.564 | **22.327** | 22.688 | 66.173 | 3754.278 |
| `binary_search` | 39.635 | **32.176** | 41.328 | 112.897 | 5261.780 |
| `sort_window` | **39.809** | 39.914 | 40.923 | 182.084 | 9434.782 |
| `bloom_filter` | **14.398** | 14.547 | 14.827 | 2430.812 | 6505.296 |
| `hash_join` | **24.634** | 24.901 | 25.750 | 3040.653 | 7181.427 |
| `sieve` | 38.692 | **37.901** | 38.060 | 85.412 | 2657.736 |
| `fib` | **28.166** | 30.208 | 29.620 | 114.174 | 910.803 |
| `collatz` | **14.938** | 15.243 | 15.931 | 59.476 | 578.300 |
| `matmul` | **20.432** | 20.499 | 20.559 | 75.609 | 2628.225 |
| `json_parse` | **7.016** | 7.507 | 9.558 | 32.217 | 33.848 |
| `nbody` | **22.547** | 31.750 | 22.629 | 80.665 | 2144.648 |
| `chacha20` | **8.144** | 37.380 | 31.959 | n/a | n/a |
| `poly1305` | **12.870** | 34.692 | 23.169 | n/a | n/a |
| `blake2b` | **43.276** | 49.715 | 52.965 | n/a | n/a |
| `sha512` | **42.143** | 43.932 | 45.425 | n/a | n/a |
| `x25519` | **28.753** | 42.774 | 41.984 | n/a | n/a |

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
| _(floor: empty program)_ | _4.404_ | _102.572_ | _**106.976**_ | _55.980_ | _68.601_ | _56.262_ |
| `lcg` | 4.411 | 112.783 | **117.194** | 54.919 | 75.024 | 62.894 |
| `packet_classifier` | 4.560 | 114.312 | **118.872** | 55.277 | 78.530 | 64.988 |
| `ring_write` | 15.203 | 115.149 | **130.352** | 65.502 | 76.129 | 62.861 |
| `histogram_bins` | 15.168 | 115.578 | **130.746** | 65.031 | 95.460 | 72.118 |
| `prefix_scan` | 15.378 | 117.871 | **133.249** | 66.003 | 87.408 | 68.954 |
| `binary_search` | 15.129 | 113.929 | **129.058** | 64.874 | 78.620 | 74.129 |
| `sort_window` | 15.680 | 118.287 | **133.967** | 65.435 | 88.468 | 74.078 |
| `bloom_filter` | 15.897 | 115.781 | **131.678** | 65.125 | 84.498 | 68.671 |
| `hash_join` | 19.076 | 229.539 | **248.615** | 70.017 | 185.772 | 129.488 |
| `sieve` | 15.182 | 111.241 | **126.423** | 62.544 | 81.472 | 73.865 |
| `fib` | 4.558 | 109.822 | **114.380** | 54.981 | 75.665 | 65.016 |
| `collatz` | 4.706 | 111.238 | **115.944** | 52.825 | 73.237 | 61.365 |
| `matmul` | 16.551 | 110.169 | **126.720** | 63.351 | 83.670 | 84.273 |
| `json_parse` | 47.964 | 416.577 | **464.541** | 99.412 | 134.843 | 172.291 |
| `nbody` | 17.667 | 118.639 | **136.306** | 66.007 | 105.135 | 98.107 |
| `chacha20` | 52.202 | 679.320 | **731.522** | 104.285 | 116.347 | 111.604 |
| `poly1305` | 40.650 | 458.474 | **499.124** | 92.352 | 121.329 | 126.107 |
| `blake2b` | 37.117 | 337.920 | **375.037** | 88.582 | 124.471 | 120.179 |
| `sha512` | 37.264 | 416.844 | **454.108** | 87.813 | 113.627 | 104.637 |
| `x25519` | 48.652 | 1201.083 | **1249.735** | 101.017 | 1172.936 | 495.995 |

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
