# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T06:10:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `489cb7b81c2b37d18a6254ec93a5300042d9394c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41175205980 |
| NURL | `v0.81.0-47-g489cb7b8` |
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
| _(floor: empty program)_ | _2.863_ | _2.729_ | _2.982_ | _22.276_ | _11.543_ |
| `lcg` | 31.147 | **30.933** | 31.743 | 1173.368 | 2844.647 |
| `packet_classifier` | **44.220** | 44.869 | 46.196 | 132.930 | 2492.300 |
| `ring_write` | **31.890** | 31.916 | 32.484 | 54.717 | 3504.332 |
| `histogram_bins` | 31.513 | **31.444** | 31.593 | 53.238 | 3229.285 |
| `prefix_scan` | **17.040** | 17.520 | 17.963 | 49.577 | 2222.307 |
| `binary_search` | 16.226 | **15.926** | 18.415 | 74.632 | 3372.519 |
| `sort_window` | 21.199 | **20.983** | 21.220 | 130.851 | 6393.323 |
| `bloom_filter` | 10.201 | **9.997** | 10.272 | 1574.439 | 4098.966 |
| `hash_join` | **16.801** | 17.547 | 19.787 | 1861.649 | 4192.663 |
| `sieve` | 16.564 | **15.845** | 16.238 | 53.060 | 1650.801 |
| `fib` | **19.909** | 19.910 | 20.029 | 76.045 | 550.080 |
| `collatz` | 11.284 | **11.159** | 11.238 | 40.543 | 376.779 |
| `matmul` | **21.505** | 21.567 | 22.115 | 54.734 | 1593.849 |
| `json_parse` | **6.593** | 8.643 | 12.302 | 28.992 | 23.824 |
| `nbody` | **17.228** | 27.065 | 19.742 | 64.945 | 1407.867 |
| `chacha20` | **8.356** | 21.148 | 20.411 | n/a | n/a |
| `poly1305` | **10.112** | 28.948 | 17.576 | n/a | n/a |
| `blake2b` | **26.952** | 45.151 | 50.380 | n/a | n/a |
| `sha512` | 30.838 | **30.773** | 32.936 | n/a | n/a |
| `x25519` | **20.716** | 31.273 | 31.941 | n/a | n/a |

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
| _(floor: empty program)_ | _5.566_ | _97.010_ | _**102.576**_ | _51.473_ | _67.706_ | _53.450_ |
| `lcg` | 5.570 | 100.996 | **106.566** | 51.924 | 78.168 | 115.013 |
| `packet_classifier` | 5.532 | 99.646 | **105.178** | 51.141 | 75.290 | 60.732 |
| `ring_write` | 11.825 | 98.049 | **109.874** | 56.295 | 74.733 | 61.645 |
| `histogram_bins` | 12.837 | 104.775 | **117.612** | 59.709 | 100.540 | 65.538 |
| `prefix_scan` | 12.155 | 98.326 | **110.481** | 55.925 | 72.866 | 60.607 |
| `binary_search` | 12.089 | 99.289 | **111.378** | 56.490 | 77.002 | 62.164 |
| `sort_window` | 11.780 | 97.151 | **108.931** | 57.375 | 80.962 | 68.446 |
| `bloom_filter` | 12.088 | 99.014 | **111.102** | 55.553 | 78.539 | 65.190 |
| `hash_join` | 13.923 | 165.296 | **179.219** | 56.638 | 135.383 | 91.241 |
| `sieve` | 12.090 | 99.776 | **111.866** | 56.209 | 81.635 | 68.337 |
| `fib` | 5.678 | 99.519 | **105.197** | 50.140 | 73.548 | 59.118 |
| `collatz` | 5.626 | 102.049 | **107.675** | 52.622 | 77.153 | 60.792 |
| `matmul` | 12.423 | 100.724 | **113.147** | 58.078 | 84.191 | 75.680 |
| `json_parse` | 33.652 | 289.242 | **322.894** | 81.071 | 112.658 | 131.186 |
| `nbody` | 13.613 | 107.828 | **121.441** | 60.229 | 100.501 | 83.642 |
| `chacha20` | 34.451 | 465.882 | **500.333** | 80.962 | 104.723 | 96.988 |
| `poly1305` | 28.495 | 320.009 | **348.504** | 72.622 | 108.033 | 104.536 |
| `blake2b` | 26.431 | 221.465 | **247.896** | 75.175 | 109.974 | 102.689 |
| `sha512` | 26.553 | 281.383 | **307.936** | 71.650 | 102.721 | 89.530 |
| `x25519` | 33.577 | 890.845 | **924.422** | 80.718 | 722.534 | 327.470 |

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
