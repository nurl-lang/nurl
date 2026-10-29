# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T01:27:30Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `56babd01961f08aebad29dd507ca28f536f1e3b1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40799778595 |
| NURL | `v0.80.0-23-g56babd01` |
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
| _(floor: empty program)_ | _1.533_ | _1.530_ | _1.724_ | _25.436_ | _18.019_ |
| `lcg` | 39.299 | **39.141** | 39.418 | 1818.522 | 5012.317 |
| `packet_classifier` | 56.495 | **56.363** | 56.660 | 162.824 | 4298.958 |
| `ring_write` | **42.412** | 42.517 | 42.784 | 68.202 | 6582.842 |
| `histogram_bins` | **39.770** | 40.788 | 40.920 | 67.822 | 6336.356 |
| `prefix_scan` | **21.719** | 21.789 | 21.919 | 67.758 | 4502.851 |
| `binary_search` | 39.839 | **38.258** | 40.927 | 108.141 | 5893.474 |
| `sort_window` | **26.663** | 26.678 | 26.994 | 198.676 | 11595.709 |
| `bloom_filter` | **16.708** | 17.989 | 18.587 | 2888.671 | 7818.854 |
| `hash_join` | **26.876** | 28.102 | 29.226 | 3476.680 | 8240.893 |
| `sieve` | 22.872 | 22.576 | **22.350** | 70.434 | 3173.042 |
| `fib` | **25.232** | 29.925 | 30.070 | 132.956 | 1396.812 |
| `collatz` | 12.426 | **12.273** | 12.478 | 51.705 | 746.437 |
| `matmul` | **33.557** | 33.570 | 33.816 | 78.388 | 3397.090 |
| `json_parse` | **8.486** | 8.702 | 11.992 | 38.522 | 41.498 |
| `nbody` | **25.320** | 40.115 | 25.630 | 104.980 | 3141.081 |
| `chacha20` | **7.428** | 40.707 | 33.967 | n/a | n/a |
| `poly1305` | **11.774** | 32.052 | 21.325 | n/a | n/a |
| `blake2b` | **44.138** | 65.010 | 69.115 | n/a | n/a |
| `sha512` | **47.606** | 50.651 | 49.605 | n/a | n/a |
| `x25519` | **31.609** | 48.337 | 49.457 | n/a | n/a |

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
| _(floor: empty program)_ | _4.849_ | _123.769_ | _**128.618**_ | _66.309_ | _85.153_ | _64.056_ |
| `lcg` | 4.838 | 130.508 | **135.346** | 65.809 | 95.950 | 72.299 |
| `packet_classifier` | 5.034 | 132.299 | **137.333** | 64.505 | 95.392 | 71.777 |
| `ring_write` | 15.983 | 138.208 | **154.191** | 76.364 | 98.713 | 72.660 |
| `histogram_bins` | 16.066 | 138.074 | **154.140** | 78.208 | 115.541 | 81.556 |
| `prefix_scan` | 15.778 | 136.497 | **152.275** | 74.933 | 100.990 | 79.919 |
| `binary_search` | 15.896 | 133.680 | **149.576** | 74.336 | 95.973 | 77.256 |
| `sort_window` | 15.961 | 137.431 | **153.392** | 77.662 | 108.010 | 83.966 |
| `bloom_filter` | 16.606 | 136.917 | **153.523** | 74.805 | 106.891 | 78.692 |
| `hash_join` | 19.883 | 266.399 | **286.282** | 77.731 | 221.705 | 125.188 |
| `sieve` | 16.161 | 137.841 | **154.002** | 76.760 | 109.619 | 86.541 |
| `fib` | 5.156 | 135.584 | **140.740** | 66.678 | 97.078 | 73.662 |
| `collatz` | 5.107 | 135.386 | **140.493** | 65.542 | 96.619 | 71.911 |
| `matmul` | 17.131 | 133.704 | **150.835** | 75.511 | 108.591 | 93.158 |
| `json_parse` | 51.450 | 483.532 | **534.982** | 113.669 | 169.950 | 176.628 |
| `nbody` | 19.128 | 145.927 | **165.055** | 80.019 | 135.696 | 111.393 |
| `chacha20` | 57.803 | 763.039 | **820.842** | 119.720 | 147.858 | 123.400 |
| `poly1305` | 45.279 | 525.493 | **570.772** | 107.518 | 149.272 | 137.484 |
| `blake2b` | 40.263 | 383.156 | **423.419** | 101.439 | 153.023 | 132.832 |
| `sha512` | 40.478 | 482.927 | **523.405** | 101.192 | 146.096 | 119.917 |
| `x25519` | 54.361 | 1305.433 | **1359.794** | 115.258 | 1230.468 | 515.106 |

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
