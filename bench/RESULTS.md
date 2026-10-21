# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-21T10:22:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `47e0d1f221e8b6ca11ddbc1d8bf6ff101cb891da` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39583435867 |
| NURL | `v0.76.0-6-g47e0d1f2` |
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
| _(floor: empty program)_ | _1.541_ | _1.506_ | _1.693_ | _22.806_ | _17.303_ |
| `lcg` | **39.084** | 39.101 | 39.350 | 1881.684 | 5106.369 |
| `packet_classifier` | **56.154** | 56.188 | 56.441 | 162.164 | 4393.237 |
| `ring_write` | 42.269 | **42.184** | 42.387 | 66.899 | 6767.187 |
| `histogram_bins` | **39.254** | 40.812 | 40.984 | 67.028 | 6094.007 |
| `prefix_scan` | **21.869** | 21.908 | 22.142 | 68.536 | 4546.767 |
| `binary_search` | 39.765 | **38.567** | 40.979 | 108.421 | 6180.834 |
| `sort_window` | 26.796 | **26.748** | 26.845 | 198.220 | 11389.628 |
| `bloom_filter` | **15.634** | 18.263 | 18.660 | 2870.537 | 7457.211 |
| `hash_join` | **26.743** | 28.197 | 29.417 | 3428.691 | 8341.647 |
| `sieve` | 22.500 | 22.072 | **21.779** | 69.610 | 3647.075 |
| `fib` | **25.261** | 29.918 | 30.073 | 134.566 | 1386.128 |
| `collatz` | 12.328 | **12.170** | 12.490 | 49.824 | 740.796 |
| `matmul` | 33.801 | **33.689** | 33.988 | 77.692 | 3178.227 |
| `json_parse` | **8.475** | 8.652 | 11.917 | 36.866 | 38.492 |
| `nbody` | **25.326** | 39.791 | 25.486 | 102.270 | 3078.283 |
| `chacha20` | **7.660** | 42.480 | 33.707 | n/a | n/a |
| `poly1305` | 23.601 | 31.936 | **21.145** | n/a | n/a |
| `blake2b` | **43.764** | 65.121 | 69.331 | n/a | n/a |
| `sha512` | **47.367** | 50.501 | 49.632 | n/a | n/a |
| `x25519` | **44.528** | 48.830 | 49.413 | n/a | n/a |

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
| _(floor: empty program)_ | _4.300_ | _107.647_ | _**111.947**_ | _65.039_ | _82.448_ | _62.598_ |
| `lcg` | 4.354 | 117.154 | **121.508** | 62.937 | 91.706 | 69.488 |
| `packet_classifier` | 4.427 | 117.162 | **121.589** | 63.393 | 93.172 | 70.454 |
| `ring_write` | 13.332 | 119.945 | **133.277** | 71.597 | 95.109 | 72.653 |
| `histogram_bins` | 13.552 | 128.730 | **142.282** | 73.908 | 115.238 | 79.658 |
| `prefix_scan` | 13.691 | 123.268 | **136.959** | 73.886 | 102.652 | 76.723 |
| `binary_search` | 13.880 | 123.231 | **137.111** | 74.599 | 100.132 | 79.332 |
| `sort_window` | 14.087 | 126.658 | **140.745** | 74.652 | 110.986 | 85.143 |
| `bloom_filter` | 14.502 | 127.820 | **142.322** | 75.843 | 109.578 | 79.901 |
| `hash_join` | 18.750 | 278.460 | **297.210** | 82.041 | 226.445 | 128.656 |
| `sieve` | 13.691 | 120.576 | **134.267** | 72.649 | 106.194 | 83.789 |
| `fib` | 4.600 | 118.991 | **123.591** | 64.780 | 96.601 | 71.171 |
| `collatz` | 4.647 | 118.634 | **123.281** | 62.803 | 94.450 | 71.468 |
| `matmul` | 15.207 | 122.549 | **137.756** | 73.855 | 110.401 | 92.737 |
| `json_parse` | 46.938 | 490.622 | **537.560** | 108.502 | 164.289 | 175.163 |
| `nbody` | 16.179 | 140.139 | **156.318** | 74.930 | 132.712 | 109.986 |
| `chacha20` | 47.723 | 796.751 | **844.474** | 109.454 | 146.899 | 123.873 |
| `poly1305` | 31.796 | 275.775 | **307.571** | 91.810 | 146.810 | 135.714 |
| `blake2b` | 36.849 | 386.608 | **423.457** | 98.363 | 150.766 | 131.901 |
| `sha512` | 35.730 | 484.575 | **520.305** | 96.682 | 144.758 | 116.754 |
| `x25519` | 40.321 | 727.802 | **768.123** | 100.619 | 1223.309 | 510.933 |

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
