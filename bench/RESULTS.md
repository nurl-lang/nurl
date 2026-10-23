# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T22:29:06Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `df39f3981b88fc523a6d5ab509af7eb05d9fc7d1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40033342921 |
| NURL | `v0.77.2-24-gdf39f398` |
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
| _(floor: empty program)_ | _1.264_ | _1.199_ | _1.362_ | _19.232_ | _13.837_ |
| `lcg` | **34.173** | 34.175 | 34.340 | 1417.178 | 4021.499 |
| `packet_classifier` | **49.234** | 49.241 | 49.412 | 123.888 | 3626.880 |
| `ring_write` | 36.933 | **36.923** | 37.103 | 58.785 | 4974.721 |
| `histogram_bins` | 34.563 | **34.549** | 34.716 | 59.032 | 4908.097 |
| `prefix_scan` | 19.005 | **18.943** | 19.151 | 57.337 | 3624.025 |
| `binary_search` | 28.096 | **27.835** | 33.891 | 88.250 | 4961.789 |
| `sort_window` | **23.188** | 23.212 | 23.386 | 129.839 | 8612.496 |
| `bloom_filter` | **13.475** | 14.599 | 16.081 | 2142.779 | 6075.312 |
| `hash_join` | **21.372** | 22.190 | 23.413 | 2682.883 | 6420.847 |
| `sieve` | 15.816 | **15.548** | 15.631 | 56.073 | 2773.953 |
| `fib` | 25.738 | **25.707** | 25.832 | 111.073 | 1011.260 |
| `collatz` | 10.644 | **10.564** | 10.753 | 39.290 | 580.727 |
| `matmul` | **35.295** | 35.897 | 35.498 | 66.298 | 2679.323 |
| `json_parse` | **6.186** | 6.820 | 9.358 | 30.065 | 30.057 |
| `nbody` | 20.882 | 34.811 | **20.822** | 75.610 | 2569.970 |
| `chacha20` | **7.011** | 35.710 | 27.630 | n/a | n/a |
| `poly1305` | 20.366 | 31.201 | **18.464** | n/a | n/a |
| `blake2b` | **37.549** | 55.523 | 60.392 | n/a | n/a |
| `sha512` | **38.541** | 40.090 | 42.234 | n/a | n/a |
| `x25519` | **38.896** | 41.955 | 43.337 | n/a | n/a |

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
| _(floor: empty program)_ | _3.889_ | _94.252_ | _**98.141**_ | _54.566_ | _69.197_ | _45.423_ |
| `lcg` | 3.835 | 103.362 | **107.197** | 54.018 | 77.117 | 49.551 |
| `packet_classifier` | 4.161 | 105.216 | **109.377** | 54.516 | 79.327 | 50.387 |
| `ring_write` | 11.292 | 108.213 | **119.505** | 62.595 | 82.211 | 52.171 |
| `histogram_bins` | 11.457 | 109.017 | **120.474** | 62.457 | 93.626 | 56.671 |
| `prefix_scan` | 11.604 | 108.036 | **119.640** | 62.314 | 84.973 | 53.656 |
| `binary_search` | 11.732 | 108.484 | **120.216** | 62.626 | 84.135 | 56.147 |
| `sort_window` | 11.905 | 111.538 | **123.443** | 63.874 | 89.148 | 58.320 |
| `bloom_filter` | 12.079 | 111.948 | **124.027** | 64.207 | 88.999 | 55.561 |
| `hash_join` | 14.704 | 209.053 | **223.757** | 65.516 | 169.512 | 89.639 |
| `sieve` | 11.668 | 106.048 | **117.716** | 61.896 | 86.904 | 58.691 |
| `fib` | 4.091 | 102.996 | **107.087** | 54.732 | 77.343 | 49.781 |
| `collatz` | 4.125 | 106.210 | **110.335** | 54.691 | 79.275 | 51.183 |
| `matmul` | 12.561 | 110.694 | **123.255** | 65.561 | 94.832 | 67.207 |
| `json_parse` | 36.898 | 370.928 | **407.826** | 87.730 | 129.915 | 126.823 |
| `nbody` | 13.543 | 114.491 | **128.034** | 64.126 | 105.864 | 78.081 |
| `chacha20` | 37.105 | 609.772 | **646.877** | 87.050 | 115.489 | 86.697 |
| `poly1305` | 25.356 | 217.394 | **242.750** | 75.538 | 116.341 | 98.141 |
| `blake2b` | 29.355 | 293.673 | **323.028** | 79.335 | 119.910 | 93.943 |
| `sha512` | 28.852 | 361.299 | **390.151** | 79.041 | 113.966 | 83.234 |
| `x25519` | 29.013 | 724.372 | **753.385** | 78.669 | 929.980 | 385.865 |

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
