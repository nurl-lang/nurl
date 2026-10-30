# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T00:25:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `0d3c2f30e374022aa73d0e9d722e4da128299704` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40979000472 |
| NURL | `v0.80.0-86-g0d3c2f30` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.4 |
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
| _(floor: empty program)_ | _1.533_ | _1.499_ | _1.704_ | _25.202_ | _18.203_ |
| `lcg` | **39.224** | 39.268 | 39.648 | 1833.847 | 5105.764 |
| `packet_classifier` | 56.530 | **56.525** | 56.717 | 164.006 | 4461.721 |
| `ring_write` | 42.357 | **42.355** | 42.540 | 70.127 | 6623.993 |
| `histogram_bins` | **39.546** | 40.809 | 40.988 | 69.205 | 6102.271 |
| `prefix_scan` | **21.940** | 22.103 | 21.993 | 68.315 | 4524.292 |
| `binary_search` | 39.741 | **38.198** | 41.035 | 108.615 | 6384.187 |
| `sort_window` | 26.901 | **26.817** | 27.077 | 198.551 | 11355.053 |
| `bloom_filter` | **16.616** | 17.938 | 18.404 | 2888.309 | 8042.391 |
| `hash_join` | **27.123** | 28.193 | 29.616 | 3486.175 | 8335.419 |
| `sieve` | 23.657 | 22.909 | **22.421** | 72.785 | 3409.396 |
| `fib` | **25.681** | 30.059 | 30.498 | 133.511 | 1347.913 |
| `collatz` | 12.485 | **12.376** | 12.635 | 51.831 | 748.152 |
| `matmul` | 34.095 | **33.848** | 34.123 | 78.771 | 3061.938 |
| `json_parse` | **8.555** | 8.829 | 12.202 | 38.064 | 40.071 |
| `nbody` | **25.500** | 40.152 | 25.708 | 104.701 | 3121.090 |
| `chacha20` | **7.483** | 40.789 | 33.948 | n/a | n/a |
| `poly1305` | **11.869** | 32.156 | 21.483 | n/a | n/a |
| `blake2b` | **44.369** | 65.343 | 69.557 | n/a | n/a |
| `sha512` | **47.619** | 50.922 | 49.934 | n/a | n/a |
| `x25519` | **31.760** | 49.232 | 49.740 | n/a | n/a |

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
| _(floor: empty program)_ | _4.725_ | _119.577_ | _**124.302**_ | _64.951_ | _81.535_ | _63.401_ |
| `lcg` | 4.960 | 134.697 | **139.657** | 66.381 | 95.730 | 72.549 |
| `packet_classifier` | 5.049 | 134.964 | **140.013** | 67.026 | 95.990 | 72.576 |
| `ring_write` | 15.496 | 133.984 | **149.480** | 75.371 | 96.953 | 72.340 |
| `histogram_bins` | 15.637 | 133.013 | **148.650** | 75.064 | 114.486 | 80.765 |
| `prefix_scan` | 15.575 | 134.470 | **150.045** | 74.537 | 101.968 | 77.213 |
| `binary_search` | 15.880 | 134.795 | **150.675** | 76.049 | 100.795 | 77.392 |
| `sort_window` | 15.887 | 135.640 | **151.527** | 74.447 | 110.284 | 83.015 |
| `bloom_filter` | 16.794 | 138.587 | **155.381** | 77.628 | 109.421 | 80.338 |
| `hash_join` | 20.011 | 268.894 | **288.905** | 81.493 | 226.048 | 126.478 |
| `sieve` | 16.308 | 137.632 | **153.940** | 77.111 | 111.801 | 90.178 |
| `fib` | 5.076 | 135.201 | **140.277** | 67.128 | 97.080 | 73.845 |
| `collatz` | 5.222 | 138.062 | **143.284** | 67.776 | 98.851 | 74.572 |
| `matmul` | 17.708 | 139.671 | **157.379** | 78.974 | 115.664 | 97.837 |
| `json_parse` | 52.405 | 482.797 | **535.202** | 115.764 | 169.870 | 180.690 |
| `nbody` | 18.820 | 143.470 | **162.290** | 80.732 | 135.723 | 113.975 |
| `chacha20` | 58.527 | 766.485 | **825.012** | 120.447 | 147.756 | 124.695 |
| `poly1305` | 44.686 | 520.758 | **565.444** | 106.721 | 149.119 | 139.643 |
| `blake2b` | 40.731 | 385.495 | **426.226** | 103.094 | 155.151 | 133.854 |
| `sha512` | 40.418 | 484.293 | **524.711** | 102.133 | 146.107 | 120.676 |
| `x25519` | 54.631 | 1305.514 | **1360.145** | 117.076 | 1239.342 | 517.061 |

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
