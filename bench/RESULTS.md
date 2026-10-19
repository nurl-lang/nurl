# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-19T20:57:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `8f2aab96de9760ce9243c703d9f7ef06f62af9c0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39322877756 |
| NURL | `v0.73.0-14-g8f2aab96` |
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
| _(floor: empty program)_ | _1.411_ | _1.438_ | _1.632_ | _22.187_ | _16.619_ |
| `lcg` | **38.959** | 39.049 | 39.169 | 1915.395 | 5519.078 |
| `packet_classifier` | 56.053 | **56.045** | 56.345 | 161.155 | 4481.372 |
| `ring_write` | **42.109** | 42.157 | 42.209 | 65.546 | 6511.326 |
| `histogram_bins` | **38.927** | 40.491 | 40.714 | 65.424 | 6228.978 |
| `prefix_scan` | 21.617 | **21.582** | 21.793 | 63.882 | 4527.963 |
| `binary_search` | 39.431 | **38.057** | 40.642 | 105.658 | 6448.288 |
| `sort_window` | 26.583 | **26.512** | 26.619 | 197.210 | 11513.451 |
| `bloom_filter` | **15.331** | 17.748 | 18.221 | 2824.535 | 7788.040 |
| `hash_join` | **26.570** | 27.777 | 29.001 | 3379.986 | 8242.957 |
| `sieve` | 20.357 | **17.746** | 18.059 | 65.690 | 3379.043 |
| `fib` | **24.976** | 29.696 | 29.758 | 130.622 | 1369.843 |
| `collatz` | 12.204 | **12.057** | 12.355 | 49.263 | 736.759 |
| `matmul` | 33.322 | **33.277** | 33.285 | 73.864 | 3751.087 |
| `json_parse` | **8.137** | 8.525 | 11.786 | 35.028 | 38.036 |
| `nbody` | **25.073** | 39.510 | 25.123 | 99.465 | 3130.240 |
| `chacha20` | **7.486** | 42.026 | 33.426 | n/a | n/a |
| `poly1305` | 23.329 | 31.661 | **21.103** | n/a | n/a |
| `blake2b` | **43.550** | 64.710 | 68.893 | n/a | n/a |
| `sha512` | **47.142** | 50.315 | 49.351 | n/a | n/a |
| `x25519` | **44.291** | 48.333 | 49.233 | n/a | n/a |

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
| _(floor: empty program)_ | _3.927_ | _95.758_ | _**99.685**_ | _58.966_ | _76.606_ | _52.057_ |
| `lcg` | 4.078 | 108.511 | **112.589** | 59.516 | 86.695 | 56.525 |
| `packet_classifier` | 4.261 | 109.522 | **113.783** | 59.213 | 87.629 | 57.233 |
| `ring_write` | 12.772 | 113.966 | **126.738** | 68.546 | 92.321 | 59.581 |
| `histogram_bins` | 12.907 | 120.230 | **133.137** | 68.440 | 105.706 | 65.576 |
| `prefix_scan` | 12.939 | 115.307 | **128.246** | 68.787 | 93.725 | 62.087 |
| `binary_search` | 13.093 | 114.351 | **127.444** | 68.702 | 90.789 | 63.126 |
| `sort_window` | 13.268 | 117.715 | **130.983** | 69.736 | 102.280 | 68.770 |
| `bloom_filter` | 13.652 | 115.930 | **129.582** | 68.863 | 99.042 | 64.218 |
| `hash_join` | 17.400 | 260.621 | **278.021** | 73.124 | 214.318 | 107.973 |
| `sieve` | 13.244 | 113.289 | **126.533** | 68.706 | 100.538 | 69.146 |
| `fib` | 4.325 | 109.529 | **113.854** | 59.805 | 87.122 | 58.040 |
| `collatz` | 4.491 | 114.930 | **119.421** | 60.934 | 91.254 | 58.736 |
| `matmul` | 14.565 | 113.792 | **128.357** | 70.440 | 103.399 | 77.819 |
| `json_parse` | 45.863 | 478.437 | **524.300** | 103.201 | 157.575 | 152.795 |
| `nbody` | 16.084 | 134.147 | **150.231** | 72.407 | 124.181 | 92.651 |
| `chacha20` | 45.678 | 766.420 | **812.098** | 101.377 | 137.068 | 103.112 |
| `poly1305` | 30.443 | 263.689 | **294.132** | 86.087 | 138.648 | 118.576 |
| `blake2b` | 34.143 | 374.557 | **408.700** | 91.147 | 144.025 | 113.068 |
| `sha512` | 34.631 | 469.618 | **504.249** | 91.135 | 136.882 | 100.267 |
| `x25519` | 39.056 | 708.204 | **747.260** | 95.211 | 1201.502 | 485.948 |

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
