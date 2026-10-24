# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-24T07:55:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `28cd9f166ebb486141c1c10278994c86332582b2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40075706737 |
| NURL | `v0.77.2-36-g28cd9f16` |
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
| _(floor: empty program)_ | _1.196_ | _1.169_ | _1.339_ | _18.096_ | _12.357_ |
| `lcg` | 29.998 | **29.715** | 29.875 | 1138.482 | 3083.834 |
| `packet_classifier` | 43.206 | **43.066** | 43.384 | 133.418 | 2865.720 |
| `ring_write` | **29.967** | 30.019 | 30.374 | 53.046 | 3725.782 |
| `histogram_bins` | **30.372** | 30.409 | 30.492 | 51.664 | 3452.791 |
| `prefix_scan` | 17.173 | **16.873** | 17.122 | 49.917 | 2544.251 |
| `binary_search` | **14.693** | 14.807 | 15.667 | 71.659 | 3743.070 |
| `sort_window` | 20.664 | **20.610** | 20.881 | 137.238 | 6406.132 |
| `bloom_filter` | 8.984 | **8.965** | 9.152 | 1644.700 | 4332.704 |
| `hash_join` | **16.304** | 17.216 | 18.259 | 1969.715 | 4699.999 |
| `sieve` | 12.249 | **12.181** | 12.579 | 46.213 | 1821.450 |
| `fib` | **19.344** | 19.391 | 19.388 | 78.617 | 689.589 |
| `collatz` | 9.689 | **9.410** | 9.698 | 38.502 | 443.406 |
| `matmul` | **20.574** | 20.954 | 21.070 | 55.930 | 1730.876 |
| `json_parse` | **4.878** | 5.461 | 7.160 | 24.595 | 24.582 |
| `nbody` | **17.023** | 24.962 | 17.351 | 60.176 | 1521.551 |
| `chacha20` | **6.659** | 19.753 | 19.464 | n/a | n/a |
| `poly1305` | **8.684** | 27.146 | 15.781 | n/a | n/a |
| `blake2b` | **26.396** | 42.347 | 47.668 | n/a | n/a |
| `sha512` | **30.668** | 33.330 | 32.419 | n/a | n/a |
| `x25519` | **26.739** | 30.368 | 29.705 | n/a | n/a |

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
| _(floor: empty program)_ | _3.991_ | _86.837_ | _**90.828**_ | _56.645_ | _65.357_ | _44.150_ |
| `lcg` | 3.490 | 92.243 | **95.733** | 47.547 | 70.397 | 47.183 |
| `packet_classifier` | 3.644 | 99.891 | **103.535** | 50.297 | 72.851 | 48.422 |
| `ring_write` | 9.503 | 97.033 | **106.536** | 54.993 | 77.204 | 50.268 |
| `histogram_bins` | 9.815 | 100.808 | **110.623** | 57.462 | 88.002 | 54.386 |
| `prefix_scan` | 9.870 | 98.851 | **108.721** | 57.526 | 80.479 | 52.224 |
| `binary_search` | 9.501 | 96.465 | **105.966** | 54.465 | 74.019 | 53.295 |
| `sort_window` | 9.927 | 98.916 | **108.843** | 56.092 | 80.911 | 54.104 |
| `bloom_filter` | 9.985 | 100.656 | **110.641** | 56.580 | 79.663 | 53.153 |
| `hash_join` | 11.841 | 176.214 | **188.055** | 57.880 | 143.055 | 82.336 |
| `sieve` | 9.495 | 96.261 | **105.756** | 54.618 | 82.619 | 56.765 |
| `fib` | 3.734 | 94.768 | **98.502** | 50.005 | 74.057 | 48.362 |
| `collatz` | 3.718 | 101.245 | **104.963** | 52.842 | 73.133 | 48.333 |
| `matmul` | 10.461 | 98.304 | **108.765** | 56.855 | 82.556 | 62.174 |
| `json_parse` | 29.403 | 315.426 | **344.829** | 74.218 | 111.145 | 120.439 |
| `nbody` | 10.457 | 97.610 | **108.067** | 54.866 | 94.778 | 74.013 |
| `chacha20` | 32.230 | 508.580 | **540.810** | 75.646 | 101.404 | 79.252 |
| `poly1305` | 25.080 | 324.478 | **349.558** | 70.322 | 101.948 | 87.918 |
| `blake2b` | 22.786 | 243.084 | **265.870** | 67.139 | 106.850 | 113.569 |
| `sha512` | 22.618 | 300.651 | **323.269** | 66.555 | 102.332 | 114.730 |
| `x25519` | 21.876 | 496.812 | **518.688** | 68.100 | 729.776 | 308.851 |

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
