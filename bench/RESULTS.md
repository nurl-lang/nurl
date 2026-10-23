# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T21:39:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `327a6fd01b98a854635724e0dc46c8ae8e7ea612` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40027642474 |
| NURL | `v0.77.2-20-g327a6fd0` |
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
| _(floor: empty program)_ | _1.518_ | _1.518_ | _1.728_ | _23.375_ | _18.295_ |
| `lcg` | **39.144** | 39.216 | 39.358 | 1898.295 | 5041.389 |
| `packet_classifier` | 56.455 | **56.343** | 56.591 | 162.767 | 4355.158 |
| `ring_write` | 42.311 | **42.282** | 42.462 | 68.259 | 6431.195 |
| `histogram_bins` | **40.574** | 40.741 | 40.858 | 67.301 | 6188.127 |
| `prefix_scan` | **21.527** | 21.682 | 22.020 | 66.220 | 4771.956 |
| `binary_search` | **38.253** | 38.534 | 40.980 | 106.494 | 9654.932 |
| `sort_window` | 26.713 | **26.598** | 27.074 | 197.126 | 11661.551 |
| `bloom_filter` | **15.369** | 17.826 | 18.373 | 2856.056 | 7621.082 |
| `hash_join` | **27.056** | 27.915 | 29.289 | 3454.534 | 8277.863 |
| `sieve` | 20.446 | 20.645 | **20.247** | 67.997 | 3240.354 |
| `fib` | 29.953 | **29.838** | 30.132 | 132.950 | 1349.474 |
| `collatz` | 12.301 | **12.156** | 12.519 | 49.959 | 747.716 |
| `matmul` | 33.682 | **33.552** | 34.044 | 77.562 | 3112.969 |
| `json_parse` | **8.230** | 8.572 | 11.787 | 36.484 | 39.714 |
| `nbody` | 25.413 | 39.916 | **25.278** | 102.004 | 3136.399 |
| `chacha20` | **7.637** | 40.486 | 33.878 | n/a | n/a |
| `poly1305` | 23.542 | 31.834 | **21.229** | n/a | n/a |
| `blake2b` | **43.657** | 64.981 | 69.132 | n/a | n/a |
| `sha512` | **47.341** | 50.697 | 49.553 | n/a | n/a |
| `x25519` | **44.293** | 48.566 | 49.513 | n/a | n/a |

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
| _(floor: empty program)_ | _4.376_ | _115.445_ | _**119.821**_ | _66.042_ | _83.661_ | _59.637_ |
| `lcg` | 4.489 | 127.992 | **132.481** | 63.747 | 93.771 | 59.422 |
| `packet_classifier` | 4.577 | 126.855 | **131.432** | 62.763 | 94.413 | 59.279 |
| `ring_write` | 13.701 | 128.741 | **142.442** | 73.193 | 94.404 | 60.493 |
| `histogram_bins` | 13.944 | 130.086 | **144.030** | 72.689 | 111.761 | 68.056 |
| `prefix_scan` | 13.862 | 130.197 | **144.059** | 72.223 | 99.822 | 63.679 |
| `binary_search` | 14.208 | 128.690 | **142.898** | 72.520 | 94.603 | 64.975 |
| `sort_window` | 14.315 | 132.863 | **147.178** | 73.744 | 107.089 | 70.712 |
| `bloom_filter` | 15.036 | 134.883 | **149.919** | 75.173 | 104.196 | 65.907 |
| `hash_join` | 18.192 | 270.480 | **288.672** | 76.843 | 221.498 | 110.065 |
| `sieve` | 14.134 | 127.563 | **141.697** | 71.826 | 104.028 | 69.638 |
| `fib` | 4.599 | 124.380 | **128.979** | 63.126 | 92.331 | 58.561 |
| `collatz` | 4.748 | 127.181 | **131.929** | 64.937 | 94.406 | 59.391 |
| `matmul` | 15.668 | 129.843 | **145.511** | 74.566 | 107.617 | 78.381 |
| `json_parse` | 48.435 | 503.758 | **552.193** | 109.365 | 164.234 | 157.564 |
| `nbody` | 16.742 | 140.337 | **157.079** | 75.134 | 130.308 | 95.922 |
| `chacha20` | 48.633 | 815.653 | **864.286** | 108.206 | 143.602 | 106.305 |
| `poly1305` | 33.087 | 287.537 | **320.624** | 92.114 | 145.034 | 120.747 |
| `blake2b` | 37.330 | 386.396 | **423.726** | 96.227 | 149.479 | 116.598 |
| `sha512` | 37.124 | 485.203 | **522.327** | 96.819 | 143.157 | 102.149 |
| `x25519` | 36.896 | 835.073 | **871.969** | 96.565 | 1234.429 | 500.393 |

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
