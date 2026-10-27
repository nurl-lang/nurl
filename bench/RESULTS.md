# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T19:49:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `153943cf0b98ee5a065f296d76fe251328bf7900` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40571572181 |
| NURL | `v0.79.0-8-g153943cf` |
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
| _(floor: empty program)_ | _1.477_ | _1.422_ | _1.690_ | _22.912_ | _17.762_ |
| `lcg` | **39.081** | 39.188 | 39.420 | 1904.387 | 5171.600 |
| `packet_classifier` | 56.284 | **56.229** | 56.494 | 163.387 | 4352.579 |
| `ring_write` | **42.327** | 42.379 | 42.486 | 67.704 | 6403.403 |
| `histogram_bins` | 40.815 | **40.781** | 41.004 | 68.271 | 6202.980 |
| `prefix_scan` | **21.683** | 21.702 | 21.992 | 67.003 | 4570.948 |
| `binary_search` | **38.185** | 38.360 | 41.247 | 107.363 | 7204.181 |
| `sort_window` | **26.737** | 26.766 | 26.888 | 197.308 | 11760.480 |
| `bloom_filter` | **15.400** | 17.929 | 18.369 | 2854.265 | 7683.174 |
| `hash_join` | **27.095** | 28.455 | 29.668 | 3441.092 | 8195.334 |
| `sieve` | 20.682 | 20.352 | **20.309** | 67.952 | 3507.992 |
| `fib` | 30.088 | **29.899** | 30.154 | 132.750 | 1381.489 |
| `collatz` | **12.362** | 12.379 | 12.488 | 51.621 | 737.287 |
| `matmul` | 33.852 | **33.483** | 33.732 | 76.487 | 3049.890 |
| `json_parse` | **8.202** | 8.599 | 11.751 | 36.089 | 39.750 |
| `nbody` | **25.481** | 39.752 | 25.484 | 99.213 | 3185.244 |
| `chacha20` | **7.268** | 42.165 | 33.844 | n/a | n/a |
| `poly1305` | **11.819** | 32.007 | 21.291 | n/a | n/a |
| `blake2b` | **43.896** | 65.273 | 69.377 | n/a | n/a |
| `sha512` | **47.359** | 50.843 | 49.672 | n/a | n/a |
| `x25519` | **44.736** | 48.865 | 49.601 | n/a | n/a |

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
| _(floor: empty program)_ | _4.305_ | _116.662_ | _**120.967**_ | _62.690_ | _80.834_ | _53.779_ |
| `lcg` | 4.636 | 129.685 | **134.321** | 63.932 | 90.973 | 58.021 |
| `packet_classifier` | 4.596 | 127.659 | **132.255** | 63.274 | 93.498 | 58.829 |
| `ring_write` | 15.848 | 142.662 | **158.510** | 77.007 | 97.948 | 63.333 |
| `histogram_bins` | 15.774 | 135.214 | **150.988** | 76.229 | 111.982 | 68.514 |
| `prefix_scan` | 15.514 | 133.342 | **148.856** | 75.138 | 99.648 | 63.085 |
| `binary_search` | 16.063 | 134.597 | **150.660** | 76.325 | 97.721 | 67.005 |
| `sort_window` | 15.888 | 136.758 | **152.646** | 76.519 | 107.211 | 73.103 |
| `bloom_filter` | 16.391 | 134.359 | **150.750** | 73.944 | 104.279 | 66.950 |
| `hash_join` | 19.913 | 272.664 | **292.577** | 77.402 | 221.800 | 110.755 |
| `sieve` | 15.792 | 132.512 | **148.304** | 74.468 | 104.548 | 71.070 |
| `fib` | 4.737 | 129.540 | **134.277** | 63.414 | 91.910 | 60.083 |
| `collatz` | 4.777 | 129.369 | **134.146** | 62.174 | 92.683 | 59.792 |
| `matmul` | 17.195 | 133.302 | **150.497** | 76.199 | 107.222 | 80.166 |
| `json_parse` | 51.279 | 507.787 | **559.066** | 111.898 | 166.189 | 159.059 |
| `nbody` | 18.724 | 143.675 | **162.399** | 78.973 | 131.350 | 96.941 |
| `chacha20` | 60.064 | 784.525 | **844.589** | 119.726 | 146.523 | 108.176 |
| `poly1305` | 45.126 | 526.376 | **571.502** | 106.618 | 146.203 | 123.256 |
| `blake2b` | 40.385 | 391.134 | **431.519** | 100.005 | 151.635 | 118.886 |
| `sha512` | 40.209 | 492.235 | **532.444** | 101.394 | 143.705 | 104.822 |
| `x25519` | 41.277 | 849.707 | **890.984** | 101.323 | 1253.086 | 499.734 |

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
