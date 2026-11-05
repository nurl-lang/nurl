# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-05T19:29:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `069be339bcc40919ae961a871e2c15c6b87f2295` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42093431548 |
| NURL | `v0.88.0` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.2 |
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
| _(floor: empty program)_ | _3.342_ | _3.298_ | _3.488_ | _26.533_ | _14.496_ |
| `lcg` | 41.147 | **40.924** | 41.169 | 1806.744 | 4880.233 |
| `packet_classifier` | 58.166 | **58.100** | 58.276 | 166.488 | 4018.392 |
| `ring_write` | 44.008 | **43.952** | 44.172 | 70.197 | 6312.328 |
| `histogram_bins` | **41.413** | 42.464 | 42.757 | 69.842 | 5598.735 |
| `prefix_scan` | 23.593 | **23.569** | 23.804 | 67.415 | 4081.019 |
| `binary_search` | 41.361 | **40.091** | 42.508 | 110.760 | 5868.790 |
| `sort_window` | 28.607 | **28.365** | 28.537 | 195.255 | 12409.378 |
| `bloom_filter` | **18.463** | 19.603 | 20.133 | 2773.966 | 6894.117 |
| `hash_join` | 28.562 | **28.431** | 30.964 | 3351.279 | 7671.698 |
| `sieve` | 24.151 | 23.829 | **23.400** | 71.993 | 3195.945 |
| `fib` | **27.251** | 31.699 | 31.801 | 135.519 | 1118.220 |
| `collatz` | 14.094 | **13.979** | 14.256 | 52.920 | 688.154 |
| `matmul` | 35.346 | **35.222** | 36.859 | 75.226 | 3077.475 |
| `json_parse` | **8.032** | 12.798 | 18.142 | 40.435 | 35.732 |
| `nbody` | **25.754** | 41.381 | 27.040 | 100.646 | 2963.007 |
| `chacha20` | **9.456** | 42.934 | 35.368 | n/a | n/a |
| `poly1305` | **13.292** | 33.582 | 22.948 | n/a | n/a |
| `blake2b` | **45.418** | 66.349 | 70.713 | n/a | n/a |
| `sha512` | 49.165 | **49.042** | 51.092 | n/a | n/a |
| `x25519` | **34.263** | 50.565 | 52.011 | n/a | n/a |

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
| _(floor: empty program)_ | _6.763_ | _117.520_ | _**124.283**_ | _62.383_ | _78.717_ | _63.446_ |
| `lcg` | 6.767 | 127.868 | **134.635** | 62.098 | 89.109 | 70.471 |
| `packet_classifier` | 6.908 | 128.130 | **135.038** | 62.171 | 88.824 | 72.296 |
| `ring_write` | 15.207 | 131.053 | **146.260** | 70.772 | 90.338 | 71.890 |
| `histogram_bins` | 15.310 | 131.990 | **147.300** | 71.444 | 133.094 | 78.684 |
| `prefix_scan` | 15.509 | 132.108 | **147.617** | 71.977 | 95.708 | 74.854 |
| `binary_search` | 15.467 | 132.109 | **147.576** | 71.561 | 91.395 | 77.437 |
| `sort_window` | 15.540 | 133.883 | **149.423** | 71.883 | 100.611 | 82.239 |
| `bloom_filter` | 16.255 | 135.155 | **151.410** | 72.307 | 100.663 | 77.831 |
| `hash_join` | 19.462 | 262.655 | **282.117** | 76.020 | 211.805 | 123.163 |
| `sieve` | 15.486 | 131.306 | **146.792** | 70.974 | 101.914 | 83.203 |
| `fib` | 6.961 | 128.282 | **135.243** | 62.699 | 88.884 | 71.776 |
| `collatz` | 6.941 | 130.727 | **137.668** | 62.370 | 93.378 | 72.361 |
| `matmul` | 15.780 | 132.313 | **148.093** | 71.763 | 104.795 | 92.298 |
| `json_parse` | 45.525 | 334.490 | **380.015** | 102.235 | 154.031 | 171.203 |
| `nbody` | 17.284 | 136.554 | **153.838** | 72.878 | 123.436 | 107.178 |
| `chacha20` | 64.848 | 674.410 | **739.258** | 121.430 | 139.443 | 119.927 |
| `poly1305` | 54.011 | 405.673 | **459.684** | 109.982 | 144.111 | 133.768 |
| `blake2b` | 35.529 | 332.541 | **368.070** | 91.842 | 142.441 | 128.529 |
| `sha512` | 34.248 | 446.606 | **480.854** | 90.542 | 135.565 | 115.302 |
| `x25519` | 49.776 | 1375.479 | **1425.255** | 105.081 | 1216.589 | 505.628 |

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
