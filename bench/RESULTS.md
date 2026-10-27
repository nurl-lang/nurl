# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T11:04:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `1c3a4c97d6c854f07ed88340787ba532c056af7f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40492585687 |
| NURL | `v0.78.0-47-g1c3a4c97` |
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
| _(floor: empty program)_ | _1.475_ | _1.416_ | _1.614_ | _24.311_ | _16.753_ |
| `lcg` | 38.999 | **38.988** | 39.130 | 1905.726 | 5102.981 |
| `packet_classifier` | 56.196 | **56.123** | 56.362 | 161.128 | 4317.186 |
| `ring_write` | 42.275 | **42.126** | 42.375 | 65.197 | 6381.999 |
| `histogram_bins` | **40.591** | 40.668 | 40.707 | 65.142 | 6077.081 |
| `prefix_scan` | **21.547** | 21.618 | 21.848 | 64.510 | 4483.462 |
| `binary_search` | 38.286 | **38.227** | 41.017 | 105.274 | 6521.218 |
| `sort_window` | **26.535** | 26.594 | 26.725 | 197.936 | 11514.661 |
| `bloom_filter` | **15.328** | 17.780 | 18.300 | 2828.243 | 7782.739 |
| `hash_join` | **26.954** | 28.215 | 29.087 | 3384.942 | 8476.404 |
| `sieve` | 19.735 | **19.495** | 19.612 | 66.355 | 3414.014 |
| `fib` | 29.984 | **29.710** | 29.910 | 131.292 | 1359.776 |
| `collatz` | 12.165 | **12.149** | 12.382 | 48.293 | 750.948 |
| `matmul` | 33.359 | **33.300** | 33.582 | 74.877 | 3139.850 |
| `json_parse` | **8.066** | 8.564 | 11.781 | 34.478 | 37.647 |
| `nbody` | 25.317 | 39.658 | **25.237** | 100.346 | 3158.708 |
| `chacha20` | **7.338** | 41.802 | 33.566 | n/a | n/a |
| `poly1305` | **11.752** | 31.733 | 21.099 | n/a | n/a |
| `blake2b` | **43.496** | 64.921 | 69.186 | n/a | n/a |
| `sha512` | **46.720** | 50.508 | 49.427 | n/a | n/a |
| `x25519` | **44.176** | 48.487 | 49.397 | n/a | n/a |

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
| _(floor: empty program)_ | _4.341_ | _110.864_ | _**115.205**_ | _58.859_ | _76.842_ | _51.302_ |
| `lcg` | 4.516 | 121.987 | **126.503** | 60.018 | 85.413 | 57.519 |
| `packet_classifier` | 4.528 | 121.855 | **126.383** | 60.039 | 86.415 | 57.595 |
| `ring_write` | 14.866 | 124.651 | **139.517** | 70.586 | 88.887 | 60.147 |
| `histogram_bins` | 15.030 | 125.981 | **141.011** | 70.735 | 105.425 | 66.458 |
| `prefix_scan` | 15.137 | 125.868 | **141.005** | 70.723 | 92.975 | 61.937 |
| `binary_search` | 15.179 | 125.305 | **140.484** | 71.125 | 90.069 | 64.034 |
| `sort_window` | 15.364 | 128.136 | **143.500** | 71.149 | 100.824 | 68.913 |
| `bloom_filter` | 15.849 | 129.762 | **145.611** | 72.472 | 98.007 | 65.237 |
| `hash_join` | 19.640 | 260.906 | **280.546** | 74.052 | 213.400 | 109.383 |
| `sieve` | 15.536 | 125.269 | **140.805** | 71.950 | 99.083 | 69.366 |
| `fib` | 4.651 | 122.908 | **127.559** | 60.384 | 86.904 | 58.954 |
| `collatz` | 4.756 | 123.666 | **128.422** | 60.195 | 89.228 | 58.191 |
| `matmul` | 16.928 | 126.232 | **143.160** | 72.783 | 101.694 | 78.208 |
| `json_parse` | 50.177 | 483.522 | **533.699** | 106.348 | 156.176 | 152.997 |
| `nbody` | 17.936 | 135.109 | **153.045** | 73.960 | 124.610 | 93.879 |
| `chacha20` | 57.432 | 745.163 | **802.595** | 112.934 | 136.292 | 103.141 |
| `poly1305` | 42.995 | 502.546 | **545.541** | 97.876 | 138.064 | 117.849 |
| `blake2b` | 38.465 | 374.112 | **412.577** | 94.194 | 141.824 | 113.120 |
| `sha512` | 38.979 | 470.326 | **509.305** | 94.854 | 134.929 | 99.946 |
| `x25519` | 39.026 | 819.607 | **858.633** | 93.867 | 1203.838 | 486.314 |

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
