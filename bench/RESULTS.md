# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T12:03:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `e12292bf9e9e0be24a6d0acf0925619459ba94e2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40318958100 |
| NURL | `v0.78.0-19-ge12292bf` |
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
| _(floor: empty program)_ | _1.226_ | _1.199_ | _1.373_ | _18.257_ | _13.682_ |
| `lcg` | 34.200 | **34.170** | 34.317 | 1406.476 | 4106.237 |
| `packet_classifier` | **49.215** | 49.223 | 49.433 | 123.401 | 3626.601 |
| `ring_write` | **36.846** | 36.978 | 37.046 | 58.671 | 5198.370 |
| `histogram_bins` | 34.682 | **34.613** | 34.712 | 60.267 | 5084.398 |
| `prefix_scan` | 18.964 | **18.878** | 19.143 | 55.286 | 3548.505 |
| `binary_search` | 27.991 | **27.574** | 33.481 | 87.381 | 5130.086 |
| `sort_window` | 23.259 | **23.194** | 23.403 | 128.069 | 8540.085 |
| `bloom_filter` | **13.376** | 14.449 | 15.994 | 2160.175 | 6334.439 |
| `hash_join` | **21.372** | 22.181 | 23.298 | 2747.838 | 6349.419 |
| `sieve` | **15.878** | 15.949 | 15.900 | 55.586 | 2890.122 |
| `fib` | 25.760 | **25.625** | 25.814 | 111.331 | 1005.692 |
| `collatz` | 10.620 | **10.543** | 10.799 | 40.423 | 583.297 |
| `matmul` | **34.851** | 35.771 | 35.458 | 67.809 | 2713.868 |
| `json_parse` | **6.238** | 6.884 | 9.370 | 29.965 | 30.574 |
| `nbody` | 20.826 | 34.841 | **20.789** | 75.930 | 2501.199 |
| `chacha20` | **6.715** | 35.762 | 27.686 | n/a | n/a |
| `poly1305` | **9.862** | 31.158 | 18.438 | n/a | n/a |
| `blake2b` | **37.626** | 55.548 | 60.607 | n/a | n/a |
| `sha512` | **38.524** | 42.892 | 42.465 | n/a | n/a |
| `x25519` | **38.119** | 42.133 | 43.394 | n/a | n/a |

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
| _(floor: empty program)_ | _3.914_ | _98.134_ | _**102.048**_ | _55.579_ | _71.025_ | _45.459_ |
| `lcg` | 3.965 | 105.733 | **109.698** | 55.733 | 79.567 | 50.150 |
| `packet_classifier` | 4.239 | 113.294 | **117.533** | 58.292 | 82.357 | 50.699 |
| `ring_write` | 12.707 | 108.961 | **121.668** | 63.667 | 80.529 | 51.320 |
| `histogram_bins` | 12.411 | 109.782 | **122.193** | 63.507 | 92.933 | 58.441 |
| `prefix_scan` | 12.527 | 111.074 | **123.601** | 64.492 | 84.425 | 54.803 |
| `binary_search` | 12.923 | 111.002 | **123.925** | 64.603 | 82.836 | 55.298 |
| `sort_window` | 12.770 | 111.114 | **123.884** | 64.146 | 89.086 | 58.564 |
| `bloom_filter` | 13.302 | 112.420 | **125.722** | 64.452 | 87.942 | 55.580 |
| `hash_join` | 16.179 | 209.446 | **225.625** | 67.709 | 174.022 | 90.624 |
| `sieve` | 12.672 | 111.098 | **123.770** | 64.581 | 90.889 | 59.468 |
| `fib` | 4.168 | 108.899 | **113.067** | 56.691 | 80.981 | 51.065 |
| `collatz` | 4.401 | 110.031 | **114.432** | 55.497 | 81.821 | 50.939 |
| `matmul` | 13.873 | 111.453 | **125.326** | 65.979 | 90.574 | 66.760 |
| `json_parse` | 40.677 | 392.960 | **433.637** | 92.941 | 132.320 | 128.431 |
| `nbody` | 14.825 | 121.393 | **136.218** | 67.632 | 110.002 | 81.766 |
| `chacha20` | 44.645 | 635.104 | **679.749** | 97.523 | 118.862 | 88.345 |
| `poly1305` | 33.754 | 396.931 | **430.685** | 85.554 | 118.860 | 98.513 |
| `blake2b` | 31.095 | 299.711 | **330.806** | 83.258 | 122.412 | 94.774 |
| `sha512` | 30.506 | 367.309 | **397.815** | 82.721 | 116.855 | 86.257 |
| `x25519` | 30.908 | 631.742 | **662.650** | 83.847 | 939.284 | 391.363 |

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
