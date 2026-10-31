# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T12:06:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `9521d65d644fe327ffd3351a35c499143ec17f34` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41199085641 |
| NURL | `v0.82.0-36-g9521d65d` |
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
| _(floor: empty program)_ | _3.299_ | _3.285_ | _3.473_ | _26.476_ | _14.753_ |
| `lcg` | 41.102 | **41.050** | 41.361 | 1796.470 | 4995.908 |
| `packet_classifier` | **58.522** | 58.549 | 58.819 | 168.111 | 4071.463 |
| `ring_write` | **44.055** | 44.367 | 44.623 | 69.832 | 6384.733 |
| `histogram_bins` | **41.686** | 42.744 | 42.695 | 69.520 | 5699.975 |
| `prefix_scan` | 23.804 | **23.675** | 23.956 | 68.640 | 4663.633 |
| `binary_search` | 41.333 | **40.010** | 42.714 | 109.291 | 6016.680 |
| `sort_window` | 28.839 | **28.645** | 28.872 | 198.218 | 11932.742 |
| `bloom_filter` | **19.055** | 20.327 | 20.677 | 2917.878 | 7373.598 |
| `hash_join` | 29.131 | **28.945** | 31.635 | 3358.467 | 7739.703 |
| `sieve` | **24.828** | 26.693 | 26.895 | 74.437 | 3440.605 |
| `fib` | **27.893** | 32.411 | 32.584 | 137.439 | 1133.117 |
| `collatz` | 14.880 | **14.796** | 14.884 | 56.111 | 689.293 |
| `matmul` | **36.454** | 36.458 | 36.555 | 76.472 | 3038.919 |
| `json_parse` | **10.985** | 13.935 | 19.065 | 41.102 | 38.105 |
| `nbody` | **26.229** | 41.960 | 27.548 | 104.230 | 2943.557 |
| `chacha20` | **9.545** | 44.450 | 35.801 | n/a | n/a |
| `poly1305` | **13.562** | 34.326 | 23.633 | n/a | n/a |
| `blake2b` | **46.347** | 67.064 | 71.553 | n/a | n/a |
| `sha512` | **49.775** | 49.955 | 52.066 | n/a | n/a |
| `x25519` | **34.012** | 51.645 | 51.943 | n/a | n/a |

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
| _(floor: empty program)_ | _6.495_ | _118.378_ | _**124.873**_ | _62.507_ | _78.476_ | _63.762_ |
| `lcg` | 6.677 | 128.387 | **135.064** | 62.803 | 88.492 | 70.972 |
| `packet_classifier` | 6.933 | 132.129 | **139.062** | 65.064 | 93.640 | 73.535 |
| `ring_write` | 17.101 | 140.030 | **157.131** | 75.344 | 92.145 | 74.593 |
| `histogram_bins` | 16.665 | 135.288 | **151.953** | 73.447 | 133.085 | 80.383 |
| `prefix_scan` | 16.614 | 133.975 | **150.589** | 72.618 | 96.290 | 77.788 |
| `binary_search` | 16.789 | 132.708 | **149.497** | 73.079 | 93.405 | 77.888 |
| `sort_window` | 16.861 | 135.179 | **152.040** | 73.503 | 102.130 | 82.711 |
| `bloom_filter` | 17.596 | 140.409 | **158.005** | 75.958 | 105.336 | 81.474 |
| `hash_join` | 21.338 | 275.524 | **296.862** | 81.467 | 222.599 | 127.856 |
| `sieve` | 17.354 | 138.141 | **155.495** | 75.713 | 103.447 | 89.153 |
| `fib` | 6.981 | 134.057 | **141.038** | 65.512 | 94.792 | 75.215 |
| `collatz` | 7.623 | 151.500 | **159.123** | 73.397 | 105.158 | 77.466 |
| `matmul` | 17.875 | 140.159 | **158.034** | 79.438 | 113.398 | 97.620 |
| `json_parse` | 51.685 | 470.615 | **522.300** | 114.272 | 167.892 | 186.873 |
| `nbody` | 19.679 | 147.873 | **167.552** | 79.923 | 133.139 | 116.654 |
| `chacha20` | 59.547 | 849.901 | **909.448** | 118.826 | 145.557 | 123.179 |
| `poly1305` | 47.094 | 353.783 | **400.877** | 108.134 | 155.505 | 143.202 |
| `blake2b` | 39.699 | 342.406 | **382.105** | 99.881 | 150.977 | 136.678 |
| `sha512` | 40.233 | 470.891 | **511.124** | 102.742 | 145.591 | 122.756 |
| `x25519` | 55.801 | 1580.219 | **1636.020** | 117.418 | 1265.069 | 524.425 |

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
