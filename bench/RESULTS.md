# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-22T03:56:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `530d39b4afe0e3503406e5884c0afba3879e339c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39718926885 |
| NURL | `v0.76.0-26-g530d39b4` |
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
| _(floor: empty program)_ | _1.577_ | _1.531_ | _1.785_ | _24.633_ | _18.064_ |
| `lcg` | **39.304** | 39.448 | 39.462 | 1931.164 | 5219.931 |
| `packet_classifier` | 56.706 | **56.574** | 56.735 | 164.151 | 4377.026 |
| `ring_write` | 42.430 | **42.340** | 42.535 | 67.311 | 6361.429 |
| `histogram_bins` | **39.784** | 40.984 | 41.250 | 69.115 | 6134.417 |
| `prefix_scan` | 22.051 | **21.959** | 22.378 | 67.111 | 4914.105 |
| `binary_search` | **36.380** | 38.325 | 41.234 | 107.895 | 5828.751 |
| `sort_window` | 26.831 | **26.707** | 26.842 | 198.798 | 11664.731 |
| `bloom_filter` | **15.783** | 18.152 | 18.685 | 2875.782 | 8057.430 |
| `hash_join` | **27.630** | 28.206 | 29.659 | 3416.026 | 8663.797 |
| `sieve` | **23.910** | 24.839 | 25.162 | 73.298 | 3341.566 |
| `fib` | **30.100** | 30.234 | 30.464 | 134.198 | 1345.292 |
| `collatz` | 12.494 | **12.463** | 12.803 | 53.484 | 742.881 |
| `matmul` | 42.621 | **33.881** | 33.987 | 78.104 | 3059.509 |
| `json_parse` | **8.533** | 8.892 | 12.222 | 39.287 | 40.779 |
| `nbody` | **25.548** | 39.955 | 25.639 | 103.547 | 3192.653 |
| `chacha20` | **7.600** | 40.682 | 33.888 | n/a | n/a |
| `poly1305` | 23.724 | 32.157 | **21.350** | n/a | n/a |
| `blake2b` | **44.045** | 65.242 | 69.198 | n/a | n/a |
| `sha512` | **47.603** | 50.916 | 49.679 | n/a | n/a |
| `x25519` | **44.418** | 48.754 | 49.614 | n/a | n/a |

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
| _(floor: empty program)_ | _4.468_ | _117.319_ | _**121.787**_ | _66.823_ | _88.251_ | _67.257_ |
| `lcg` | 4.554 | 121.263 | **125.817** | 64.685 | 96.253 | 73.291 |
| `packet_classifier` | 4.683 | 123.059 | **127.742** | 66.315 | 97.404 | 73.366 |
| `ring_write` | 13.661 | 126.667 | **140.328** | 73.982 | 97.514 | 74.572 |
| `histogram_bins` | 14.168 | 134.375 | **148.543** | 77.181 | 119.337 | 83.919 |
| `prefix_scan` | 14.213 | 129.963 | **144.176** | 77.342 | 105.107 | 77.583 |
| `binary_search` | 14.018 | 130.364 | **144.382** | 77.872 | 102.357 | 82.012 |
| `sort_window` | 14.318 | 132.774 | **147.092** | 76.668 | 112.193 | 86.023 |
| `bloom_filter` | 14.890 | 130.611 | **145.501** | 77.402 | 110.057 | 86.491 |
| `hash_join` | 18.681 | 278.926 | **297.607** | 81.554 | 231.239 | 129.720 |
| `sieve` | 14.158 | 128.453 | **142.611** | 76.361 | 112.579 | 88.102 |
| `fib` | 4.861 | 123.731 | **128.592** | 66.291 | 98.314 | 73.159 |
| `collatz` | 4.944 | 128.563 | **133.507** | 67.601 | 100.981 | 74.882 |
| `matmul` | 15.632 | 129.908 | **145.540** | 78.514 | 113.927 | 100.500 |
| `json_parse` | 47.801 | 504.403 | **552.204** | 110.050 | 169.659 | 179.226 |
| `nbody` | 16.851 | 145.072 | **161.923** | 79.272 | 135.139 | 111.842 |
| `chacha20` | 48.067 | 838.987 | **887.054** | 110.599 | 145.599 | 122.872 |
| `poly1305` | 32.459 | 279.793 | **312.252** | 94.168 | 147.748 | 138.682 |
| `blake2b` | 36.217 | 389.236 | **425.453** | 98.441 | 153.528 | 132.322 |
| `sha512` | 36.091 | 491.459 | **527.550** | 98.693 | 146.747 | 119.611 |
| `x25519` | 36.992 | 834.781 | **871.773** | 99.930 | 1246.620 | 518.710 |

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
