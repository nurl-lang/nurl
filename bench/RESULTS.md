# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-20T05:46:24Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `df213fb80d7791da9e873413c2851a28b7880018` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39376136764 |
| NURL | `v0.74.0-5-gdf213fb8` |
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
| _(floor: empty program)_ | _1.508_ | _1.500_ | _1.710_ | _21.844_ | _17.388_ |
| `lcg` | **39.090** | 39.217 | 39.477 | 1893.258 | 5045.971 |
| `packet_classifier` | **56.133** | 56.332 | 56.516 | 163.633 | 4366.569 |
| `ring_write` | **42.263** | 42.291 | 42.601 | 67.681 | 6571.533 |
| `histogram_bins` | **39.249** | 40.797 | 41.250 | 69.458 | 6119.752 |
| `prefix_scan` | 21.878 | **21.854** | 22.061 | 68.715 | 4438.123 |
| `binary_search` | 39.749 | **38.367** | 41.081 | 108.529 | 5843.941 |
| `sort_window` | 27.035 | **27.020** | 27.318 | 201.236 | 14585.718 |
| `bloom_filter` | **15.433** | 18.003 | 18.422 | 2890.198 | 7662.092 |
| `hash_join` | **26.936** | 28.538 | 29.713 | 3449.565 | 8227.933 |
| `sieve` | 24.087 | **22.982** | 23.257 | 74.648 | 3212.303 |
| `fib` | **25.255** | 30.027 | 30.088 | 132.546 | 1342.472 |
| `collatz` | **12.440** | 12.533 | 12.578 | 51.940 | 745.409 |
| `matmul` | 33.849 | **33.629** | 33.679 | 78.683 | 3177.910 |
| `json_parse` | **8.629** | 8.826 | 12.186 | 39.034 | 40.092 |
| `nbody` | **25.279** | 40.013 | 25.505 | 103.935 | 3177.273 |
| `chacha20` | **7.642** | 41.070 | 33.936 | n/a | n/a |
| `poly1305` | 23.802 | 31.962 | **21.240** | n/a | n/a |
| `blake2b` | **43.957** | 65.291 | 69.263 | n/a | n/a |
| `sha512` | **47.599** | 50.797 | 49.788 | n/a | n/a |
| `x25519` | **44.668** | 48.890 | 49.682 | n/a | n/a |

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
| _(floor: empty program)_ | _4.261_ | _104.834_ | _**109.095**_ | _64.454_ | _82.552_ | _62.872_ |
| `lcg` | 4.506 | 118.837 | **123.343** | 65.102 | 94.624 | 70.874 |
| `packet_classifier` | 4.415 | 115.593 | **120.008** | 62.752 | 92.675 | 71.095 |
| `ring_write` | 13.163 | 123.649 | **136.812** | 74.003 | 100.435 | 75.048 |
| `histogram_bins` | 13.554 | 128.995 | **142.549** | 72.748 | 113.709 | 83.091 |
| `prefix_scan` | 13.974 | 126.084 | **140.058** | 75.663 | 106.467 | 77.808 |
| `binary_search` | 14.123 | 128.209 | **142.332** | 76.306 | 101.952 | 88.047 |
| `sort_window` | 14.285 | 130.886 | **145.171** | 78.523 | 112.592 | 85.645 |
| `bloom_filter` | 14.246 | 128.221 | **142.467** | 77.318 | 111.797 | 84.402 |
| `hash_join` | 18.468 | 282.363 | **300.831** | 83.232 | 233.197 | 130.991 |
| `sieve` | 13.840 | 125.596 | **139.436** | 76.056 | 116.452 | 92.820 |
| `fib` | 4.558 | 121.912 | **126.470** | 67.019 | 98.603 | 74.281 |
| `collatz` | 4.804 | 130.916 | **135.720** | 70.906 | 100.236 | 77.055 |
| `matmul` | 15.828 | 132.047 | **147.875** | 80.475 | 119.033 | 98.997 |
| `json_parse` | 46.770 | 506.280 | **553.050** | 110.479 | 171.510 | 184.521 |
| `nbody` | 16.702 | 148.639 | **165.341** | 79.629 | 139.432 | 115.926 |
| `chacha20` | 46.662 | 802.969 | **849.631** | 108.955 | 149.986 | 126.701 |
| `poly1305` | 32.145 | 279.803 | **311.948** | 95.984 | 151.634 | 141.685 |
| `blake2b` | 35.772 | 391.896 | **427.668** | 98.525 | 155.173 | 135.801 |
| `sha512` | 35.411 | 484.428 | **519.839** | 96.955 | 146.651 | 120.162 |
| `x25519` | 40.106 | 730.410 | **770.516** | 101.595 | 1241.140 | 523.277 |

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
