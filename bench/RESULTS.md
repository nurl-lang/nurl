# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T09:47:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d216fa60484e7af06b58883c02fd606856134080` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40301616886 |
| NURL | `v0.78.0-12-gd216fa60` |
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
| _(floor: empty program)_ | _1.228_ | _1.206_ | _1.394_ | _21.756_ | _16.015_ |
| `lcg` | **34.383** | 34.441 | 34.681 | 1429.943 | 4164.315 |
| `packet_classifier` | **49.472** | 49.476 | 49.612 | 125.891 | 3766.136 |
| `ring_write` | 36.966 | **36.893** | 37.436 | 60.380 | 5254.104 |
| `histogram_bins` | 34.776 | **34.678** | 34.924 | 61.228 | 4881.673 |
| `prefix_scan` | 19.131 | **19.130** | 19.424 | 59.321 | 3574.762 |
| `binary_search` | 28.220 | **27.915** | 33.760 | 88.060 | 5601.462 |
| `sort_window` | **23.438** | 23.468 | 23.692 | 131.087 | 8571.114 |
| `bloom_filter` | **13.501** | 14.581 | 16.124 | 2146.781 | 5905.418 |
| `hash_join` | **21.517** | 22.379 | 23.516 | 2722.100 | 6405.728 |
| `sieve` | 16.582 | 16.411 | **16.366** | 57.953 | 2760.271 |
| `fib` | **25.863** | 25.945 | 26.204 | 114.304 | 997.190 |
| `collatz` | 10.801 | **10.720** | 11.014 | 43.622 | 585.336 |
| `matmul` | 36.513 | **35.941** | 36.370 | 67.192 | 2891.757 |
| `json_parse` | **6.369** | 7.085 | 9.882 | 33.153 | 33.203 |
| `nbody` | 21.208 | 35.591 | **21.083** | 79.299 | 2557.563 |
| `chacha20` | **6.907** | 35.859 | 27.905 | n/a | n/a |
| `poly1305` | **10.157** | 31.488 | 18.756 | n/a | n/a |
| `blake2b` | **37.772** | 55.723 | 61.582 | n/a | n/a |
| `sha512` | **38.699** | 40.377 | 42.567 | n/a | n/a |
| `x25519` | **38.272** | 42.245 | 43.508 | n/a | n/a |

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
| _(floor: empty program)_ | _4.144_ | _107.108_ | _**111.252**_ | _59.924_ | _77.316_ | _47.870_ |
| `lcg` | 4.285 | 114.919 | **119.204** | 58.908 | 83.403 | 52.243 |
| `packet_classifier` | 4.288 | 115.807 | **120.095** | 58.480 | 88.040 | 52.479 |
| `ring_write` | 12.288 | 118.308 | **130.596** | 67.380 | 86.685 | 54.069 |
| `histogram_bins` | 11.817 | 116.704 | **128.521** | 67.066 | 99.262 | 58.042 |
| `prefix_scan` | 12.066 | 119.665 | **131.731** | 71.031 | 91.057 | 55.912 |
| `binary_search` | 11.992 | 115.090 | **127.082** | 66.622 | 87.710 | 58.337 |
| `sort_window` | 12.451 | 119.702 | **132.153** | 68.163 | 94.994 | 62.176 |
| `bloom_filter` | 12.658 | 118.788 | **131.446** | 67.270 | 94.003 | 58.424 |
| `hash_join` | 15.438 | 215.306 | **230.744** | 69.387 | 177.614 | 94.100 |
| `sieve` | 12.005 | 116.387 | **128.392** | 67.379 | 97.135 | 62.973 |
| `fib` | 4.280 | 115.797 | **120.077** | 59.328 | 87.800 | 53.752 |
| `collatz` | 4.537 | 118.403 | **122.940** | 58.738 | 91.120 | 53.135 |
| `matmul` | 13.696 | 121.265 | **134.961** | 70.088 | 100.722 | 70.334 |
| `json_parse` | 38.992 | 387.635 | **426.627** | 94.619 | 138.598 | 135.387 |
| `nbody` | 14.560 | 125.238 | **139.798** | 69.527 | 114.470 | 82.924 |
| `chacha20` | 44.862 | 652.892 | **697.754** | 99.689 | 123.849 | 91.455 |
| `poly1305` | 34.212 | 414.012 | **448.224** | 89.049 | 125.153 | 102.451 |
| `blake2b` | 31.762 | 309.779 | **341.541** | 87.247 | 129.275 | 99.030 |
| `sha512` | 31.262 | 384.879 | **416.141** | 86.728 | 123.568 | 87.598 |
| `x25519` | 30.671 | 643.924 | **674.595** | 85.430 | 960.155 | 399.963 |

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
