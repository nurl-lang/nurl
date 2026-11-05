# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-05T09:31:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `cfcfe5bb689b64dd4fe68df2ead4dc7eec5a6b5b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42002508923 |
| NURL | `v0.86.0-11-gcfcfe5bb` |
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
| _(floor: empty program)_ | _2.756_ | _2.607_ | _2.785_ | _20.507_ | _10.646_ |
| `lcg` | 30.700 | **30.495** | 30.648 | 1148.662 | 2846.075 |
| `packet_classifier` | **42.365** | 44.035 | 43.249 | 133.817 | 2585.452 |
| `ring_write` | 30.138 | **29.918** | 30.189 | 53.207 | 3385.708 |
| `histogram_bins` | 30.493 | **29.880** | 30.058 | 53.136 | 3007.015 |
| `prefix_scan` | 17.351 | **17.230** | 17.403 | 48.526 | 2321.012 |
| `binary_search` | 16.162 | **15.719** | 16.751 | 70.587 | 3554.929 |
| `sort_window` | 21.722 | **21.440** | 21.683 | 133.328 | 6274.211 |
| `bloom_filter` | 10.605 | **10.390** | 10.591 | 1602.606 | 4054.313 |
| `hash_join` | **17.100** | 17.352 | 19.352 | 1891.349 | 4026.200 |
| `sieve` | 17.079 | **17.008** | 17.167 | 51.728 | 1674.640 |
| `fib` | 20.394 | 20.445 | **20.269** | 77.151 | 537.863 |
| `collatz` | 11.000 | **10.643** | 10.665 | 40.604 | 366.223 |
| `matmul` | 22.509 | 22.940 | **22.505** | 55.265 | 1591.637 |
| `json_parse` | **5.323** | 8.483 | 12.350 | 29.587 | 25.309 |
| `nbody` | **17.052** | 25.863 | 18.604 | 61.115 | 1355.591 |
| `chacha20` | **5.030** | 21.028 | 20.828 | n/a | n/a |
| `poly1305` | **7.917** | 28.003 | 16.904 | n/a | n/a |
| `blake2b` | **27.986** | 45.024 | 48.169 | n/a | n/a |
| `sha512` | **30.990** | 31.193 | 33.576 | n/a | n/a |
| `x25519` | **21.365** | 32.675 | 33.068 | n/a | n/a |

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
| _(floor: empty program)_ | _5.725_ | _96.311_ | _**102.036**_ | _58.752_ | _66.030_ | _51.419_ |
| `lcg` | 5.612 | 100.375 | **105.987** | 50.111 | 72.912 | 57.112 |
| `packet_classifier` | 5.926 | 103.058 | **108.984** | 52.175 | 75.835 | 61.465 |
| `ring_write` | 10.766 | 101.218 | **111.984** | 57.416 | 78.258 | 60.996 |
| `histogram_bins` | 11.263 | 107.666 | **118.929** | 58.842 | 99.016 | 67.928 |
| `prefix_scan` | 11.099 | 103.444 | **114.543** | 56.763 | 77.580 | 62.723 |
| `binary_search` | 11.337 | 103.676 | **115.013** | 57.707 | 77.575 | 65.177 |
| `sort_window` | 11.452 | 106.394 | **117.846** | 58.597 | 84.087 | 67.921 |
| `bloom_filter` | 11.137 | 103.321 | **114.458** | 56.778 | 77.730 | 65.627 |
| `hash_join` | 13.702 | 173.788 | **187.490** | 59.865 | 138.951 | 96.067 |
| `sieve` | 11.166 | 103.216 | **114.382** | 57.250 | 82.446 | 69.655 |
| `fib` | 5.613 | 96.004 | **101.617** | 51.901 | 74.903 | 58.721 |
| `collatz` | 5.850 | 100.476 | **106.326** | 50.817 | 76.655 | 62.787 |
| `matmul` | 10.945 | 104.472 | **115.417** | 56.303 | 86.147 | 79.623 |
| `json_parse` | 28.927 | 225.868 | **254.795** | 76.270 | 114.943 | 136.949 |
| `nbody` | 12.426 | 107.988 | **120.414** | 59.036 | 100.234 | 87.344 |
| `chacha20` | 38.760 | 483.683 | **522.443** | 85.341 | 105.562 | 93.856 |
| `poly1305` | 32.726 | 283.298 | **316.024** | 80.161 | 111.506 | 102.873 |
| `blake2b` | 23.425 | 225.883 | **249.308** | 71.837 | 110.327 | 102.255 |
| `sha512` | 22.378 | 281.232 | **303.610** | 68.987 | 104.682 | 92.245 |
| `x25519` | 31.422 | 817.276 | **848.698** | 78.438 | 729.658 | 329.583 |

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
