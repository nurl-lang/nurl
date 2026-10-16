# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-16T13:30:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `5d0e0ab4bf4fd6cc069ee65ce478036ac5aa75e3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38907656879 |
| NURL | `v0.73.0` |
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
| _(floor: empty program)_ | _1.517_ | _1.455_ | _1.650_ | _21.672_ | _17.016_ |
| `lcg` | 39.026 | **39.003** | 39.152 | 1907.546 | 5087.650 |
| `packet_classifier` | **56.088** | 56.131 | 56.239 | 160.928 | 4447.811 |
| `ring_write` | 42.102 | **42.099** | 42.194 | 64.141 | 6429.044 |
| `histogram_bins` | **39.016** | 40.467 | 40.667 | 64.495 | 6179.419 |
| `prefix_scan` | **21.569** | 21.638 | 21.806 | 63.550 | 4622.520 |
| `binary_search` | 39.464 | **38.178** | 40.907 | 105.570 | 6075.101 |
| `sort_window` | 26.519 | **26.439** | 26.621 | 196.265 | 12267.210 |
| `bloom_filter` | **15.297** | 17.778 | 18.307 | 2838.417 | 7507.849 |
| `hash_join` | **26.483** | 27.783 | 29.061 | 3427.667 | 8597.186 |
| `sieve` | 18.106 | **17.698** | 17.830 | 65.213 | 3224.233 |
| `fib` | **25.027** | 29.771 | 29.958 | 130.470 | 1358.572 |
| `collatz` | 12.304 | **12.196** | 12.453 | 48.110 | 750.854 |
| `matmul` | 33.330 | **33.326** | 33.516 | 74.891 | 3203.162 |
| `json_parse` | **8.265** | 8.530 | 11.723 | 34.325 | 38.621 |
| `nbody` | **25.092** | 39.576 | 25.173 | 98.311 | 3103.695 |
| `chacha20` | **7.621** | 42.229 | 33.588 | n/a | n/a |
| `poly1305` | 23.370 | 31.655 | **21.097** | n/a | n/a |
| `blake2b` | **43.587** | 64.739 | 68.984 | n/a | n/a |
| `sha512` | **47.273** | 50.468 | 49.460 | n/a | n/a |
| `x25519` | **44.161** | 48.457 | 49.120 | n/a | n/a |

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
| _(floor: empty program)_ | _4.031_ | _98.303_ | _**102.334**_ | _59.060_ | _76.036_ | _51.880_ |
| `lcg` | 4.067 | 108.664 | **112.731** | 58.956 | 85.895 | 57.057 |
| `packet_classifier` | 4.210 | 108.883 | **113.093** | 58.575 | 87.051 | 57.550 |
| `ring_write` | 12.749 | 112.495 | **125.244** | 68.212 | 87.457 | 58.750 |
| `histogram_bins` | 12.920 | 120.563 | **133.483** | 68.281 | 104.972 | 65.108 |
| `prefix_scan` | 12.974 | 114.592 | **127.566** | 68.234 | 94.326 | 62.524 |
| `binary_search` | 13.143 | 114.792 | **127.935** | 69.150 | 90.351 | 63.374 |
| `sort_window` | 13.158 | 115.581 | **128.739** | 67.940 | 99.180 | 67.824 |
| `bloom_filter` | 13.595 | 116.619 | **130.214** | 69.146 | 98.292 | 65.087 |
| `hash_join` | 17.192 | 260.501 | **277.693** | 73.368 | 214.705 | 108.394 |
| `sieve` | 13.038 | 112.597 | **125.635** | 68.728 | 100.559 | 69.421 |
| `fib` | 4.335 | 109.082 | **113.417** | 59.026 | 87.232 | 58.426 |
| `collatz` | 4.403 | 111.260 | **115.663** | 58.836 | 87.926 | 57.289 |
| `matmul` | 14.337 | 113.999 | **128.336** | 69.940 | 103.058 | 78.057 |
| `json_parse` | 44.591 | 482.360 | **526.951** | 101.971 | 157.949 | 154.201 |
| `nbody` | 15.592 | 133.094 | **148.686** | 70.913 | 124.434 | 93.488 |
| `chacha20` | 45.168 | 778.409 | **823.577** | 101.135 | 137.365 | 103.572 |
| `poly1305` | 30.134 | 265.393 | **295.527** | 86.084 | 138.648 | 118.279 |
| `blake2b` | 33.822 | 377.637 | **411.459** | 89.687 | 144.232 | 114.146 |
| `sha512` | 34.150 | 470.903 | **505.053** | 91.277 | 135.340 | 98.443 |
| `x25519` | 38.602 | 713.306 | **751.908** | 94.486 | 1216.211 | 489.713 |

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
