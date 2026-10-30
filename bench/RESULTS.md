# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T23:57:07Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `73deb1a8e9cce62b9c456edddee15228d4a5fa0e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41146747580 |
| NURL | `v0.81.0-21-g73deb1a8` |
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
| _(floor: empty program)_ | _3.394_ | _3.393_ | _3.580_ | _27.623_ | _15.027_ |
| `lcg` | 41.245 | **41.231** | 41.462 | 1793.345 | 5001.143 |
| `packet_classifier` | 58.490 | **58.366** | 58.668 | 166.070 | 4032.841 |
| `ring_write` | **44.386** | 44.432 | 44.525 | 70.577 | 6350.973 |
| `histogram_bins` | **41.824** | 42.784 | 43.038 | 71.579 | 5628.874 |
| `prefix_scan` | 23.966 | **23.699** | 23.961 | 68.485 | 4135.389 |
| `binary_search` | 41.467 | **40.364** | 42.978 | 110.001 | 5886.180 |
| `sort_window` | **28.658** | 28.852 | 28.890 | 197.968 | 12181.722 |
| `bloom_filter` | **18.666** | 19.891 | 20.565 | 2863.194 | 7202.206 |
| `hash_join` | 28.713 | **28.581** | 31.237 | 3356.464 | 7818.995 |
| `sieve` | 26.168 | **25.550** | 25.691 | 73.658 | 3224.759 |
| `fib` | **27.207** | 32.007 | 32.424 | 135.238 | 1114.557 |
| `collatz` | 14.375 | **14.203** | 14.464 | 52.733 | 689.383 |
| `matmul` | 35.849 | **35.537** | 35.893 | 74.130 | 2998.729 |
| `json_parse` | **10.516** | 13.385 | 18.962 | 41.435 | 36.794 |
| `nbody` | **26.118** | 41.670 | 27.544 | 103.079 | 2963.115 |
| `chacha20` | **9.257** | 44.460 | 35.698 | n/a | n/a |
| `poly1305` | **13.311** | 33.831 | 23.177 | n/a | n/a |
| `blake2b` | **46.308** | 67.079 | 71.220 | n/a | n/a |
| `sha512` | 49.661 | **49.515** | 51.600 | n/a | n/a |
| `x25519` | **33.743** | 51.141 | 51.605 | n/a | n/a |

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
| _(floor: empty program)_ | _6.771_ | _115.891_ | _**122.662**_ | _64.975_ | _79.480_ | _63.682_ |
| `lcg` | 6.776 | 124.295 | **131.071** | 62.894 | 89.257 | 70.615 |
| `packet_classifier` | 6.893 | 124.397 | **131.290** | 64.285 | 91.684 | 72.109 |
| `ring_write` | 17.427 | 126.883 | **144.310** | 74.028 | 92.388 | 73.258 |
| `histogram_bins` | 17.478 | 130.914 | **148.392** | 74.529 | 135.166 | 80.243 |
| `prefix_scan` | 17.624 | 129.472 | **147.096** | 74.379 | 97.990 | 77.226 |
| `binary_search` | 17.753 | 127.972 | **145.725** | 74.651 | 94.413 | 77.899 |
| `sort_window` | 17.749 | 129.422 | **147.171** | 74.836 | 103.057 | 83.107 |
| `bloom_filter` | 18.408 | 133.535 | **151.943** | 76.109 | 103.887 | 79.742 |
| `hash_join` | 21.720 | 265.611 | **287.331** | 78.222 | 216.125 | 124.627 |
| `sieve` | 17.654 | 127.247 | **144.901** | 74.516 | 103.522 | 84.562 |
| `fib` | 6.946 | 124.871 | **131.817** | 64.287 | 90.162 | 71.754 |
| `collatz` | 7.053 | 127.596 | **134.649** | 64.997 | 97.265 | 77.513 |
| `matmul` | 19.125 | 129.622 | **148.747** | 75.845 | 106.958 | 94.932 |
| `json_parse` | 53.260 | 452.817 | **506.077** | 112.923 | 160.375 | 178.571 |
| `nbody` | 20.532 | 135.159 | **155.691** | 78.020 | 127.720 | 109.227 |
| `chacha20` | 59.719 | 778.582 | **838.301** | 117.925 | 142.291 | 122.714 |
| `poly1305` | 46.136 | 507.616 | **553.752** | 103.820 | 148.375 | 137.212 |
| `blake2b` | 41.036 | 333.923 | **374.959** | 99.243 | 146.126 | 131.018 |
| `sha512` | 41.778 | 453.878 | **495.656** | 99.464 | 139.232 | 117.569 |
| `x25519` | 55.538 | 1543.639 | **1599.177** | 114.147 | 1249.777 | 513.925 |

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
