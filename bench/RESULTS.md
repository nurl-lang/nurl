# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T00:35:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `9f7dd29dfe91369b984a0d3f32cd6fb620849250` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41150475934 |
| NURL | `v0.81.0-27-g9f7dd29d` |
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
| _(floor: empty program)_ | _3.472_ | _3.426_ | _3.711_ | _30.836_ | _15.305_ |
| `lcg` | 41.464 | **41.383** | 41.683 | 1796.043 | 4865.316 |
| `packet_classifier` | 58.803 | **58.729** | 59.280 | 168.876 | 4074.691 |
| `ring_write` | 45.359 | **45.055** | 45.173 | 73.306 | 6165.506 |
| `histogram_bins` | **42.268** | 43.308 | 43.430 | 73.114 | 5583.272 |
| `prefix_scan` | 24.273 | **24.238** | 24.392 | 70.200 | 4142.041 |
| `binary_search` | 42.388 | **40.916** | 44.061 | 113.936 | 5902.087 |
| `sort_window` | **29.243** | 29.343 | 29.647 | 200.688 | 12099.221 |
| `bloom_filter` | **18.969** | 20.014 | 20.591 | 2860.036 | 7188.756 |
| `hash_join` | 29.305 | **29.109** | 31.906 | 3399.071 | 7657.615 |
| `sieve` | 29.048 | **28.846** | 28.878 | 76.570 | 3114.105 |
| `fib` | **28.075** | 32.690 | 32.716 | 139.419 | 1103.325 |
| `collatz` | 14.998 | **14.889** | 14.920 | 56.224 | 688.972 |
| `matmul` | 36.307 | **36.106** | 36.477 | 81.366 | 2850.291 |
| `json_parse` | **10.659** | 13.820 | 18.990 | 41.570 | 36.921 |
| `nbody` | **26.949** | 42.564 | 27.678 | 106.364 | 3023.938 |
| `chacha20` | **9.735** | 43.811 | 36.073 | n/a | n/a |
| `poly1305` | **13.785** | 34.097 | 23.291 | n/a | n/a |
| `blake2b` | **46.856** | 67.205 | 71.889 | n/a | n/a |
| `sha512` | **50.102** | 50.285 | 52.472 | n/a | n/a |
| `x25519` | **33.673** | 51.391 | 51.950 | n/a | n/a |

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
| _(floor: empty program)_ | _7.023_ | _125.844_ | _**132.867**_ | _71.409_ | _88.141_ | _68.719_ |
| `lcg` | 6.940 | 131.554 | **138.494** | 66.631 | 96.760 | 76.810 |
| `packet_classifier` | 7.283 | 135.367 | **142.650** | 71.112 | 102.427 | 80.320 |
| `ring_write` | 17.707 | 140.092 | **157.799** | 80.106 | 105.082 | 79.972 |
| `histogram_bins` | 18.120 | 139.844 | **157.964** | 81.327 | 146.950 | 86.391 |
| `prefix_scan` | 18.624 | 140.299 | **158.923** | 81.821 | 108.183 | 86.095 |
| `binary_search` | 18.818 | 138.244 | **157.062** | 81.661 | 107.208 | 82.469 |
| `sort_window` | 18.254 | 139.862 | **158.116** | 80.422 | 111.990 | 90.995 |
| `bloom_filter` | 18.779 | 138.011 | **156.790** | 80.170 | 111.181 | 84.692 |
| `hash_join` | 22.095 | 273.147 | **295.242** | 83.291 | 230.763 | 130.641 |
| `sieve` | 18.948 | 141.046 | **159.994** | 84.229 | 114.821 | 99.448 |
| `fib` | 7.360 | 135.591 | **142.951** | 70.333 | 101.396 | 82.488 |
| `collatz` | 7.566 | 138.531 | **146.097** | 70.446 | 103.854 | 80.956 |
| `matmul` | 19.860 | 139.800 | **159.660** | 82.436 | 115.706 | 104.507 |
| `json_parse` | 55.187 | 471.862 | **527.049** | 119.561 | 165.480 | 182.618 |
| `nbody` | 20.401 | 142.411 | **162.812** | 79.533 | 137.442 | 121.113 |
| `chacha20` | 61.091 | 799.327 | **860.418** | 122.610 | 153.497 | 128.160 |
| `poly1305` | 47.816 | 521.030 | **568.846** | 113.079 | 157.865 | 143.893 |
| `blake2b` | 41.584 | 348.872 | **390.456** | 103.419 | 160.743 | 136.551 |
| `sha512` | 42.875 | 472.648 | **515.523** | 106.999 | 153.400 | 126.442 |
| `x25519` | 58.176 | 1581.185 | **1639.361** | 126.866 | 1280.038 | 521.584 |

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
