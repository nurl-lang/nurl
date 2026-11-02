# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-02T10:51:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2430673dfb53385696ff11315ce0bbaa1a7a9cb3` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41431413738 |
| NURL | `v0.85.0` |
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
| _(floor: empty program)_ | _3.615_ | _3.537_ | _3.912_ | _28.533_ | _16.491_ |
| `lcg` | 41.923 | **41.788** | 42.049 | 1797.456 | 5116.894 |
| `packet_classifier` | 58.887 | **58.823** | 59.077 | 167.812 | 4039.023 |
| `ring_write` | 45.119 | 44.997 | **44.973** | 73.210 | 6650.536 |
| `histogram_bins` | **42.094** | 43.236 | 43.371 | 71.623 | 5750.360 |
| `prefix_scan` | 24.364 | **24.232** | 24.433 | 71.153 | 4201.104 |
| `binary_search` | 42.367 | **40.853** | 43.674 | 112.474 | 5891.289 |
| `sort_window` | **29.502** | 29.611 | 29.685 | 200.970 | 12041.990 |
| `bloom_filter` | **19.083** | 20.487 | 21.201 | 2877.448 | 7194.342 |
| `hash_join` | 29.971 | **29.458** | 32.492 | 3384.524 | 7720.880 |
| `sieve` | 27.198 | 26.535 | **26.083** | 75.880 | 3067.282 |
| `fib` | **27.829** | 32.102 | 32.401 | 136.447 | 1156.593 |
| `collatz` | 14.663 | **14.562** | 14.850 | 59.516 | 700.059 |
| `matmul` | 36.046 | 35.953 | **35.829** | 76.017 | 3069.619 |
| `json_parse` | **8.541** | 13.675 | 19.260 | 43.591 | 38.862 |
| `nbody` | **26.663** | 42.567 | 28.022 | 116.760 | 2963.780 |
| `chacha20` | **10.140** | 45.162 | 36.596 | n/a | n/a |
| `poly1305` | **14.142** | 34.603 | 23.938 | n/a | n/a |
| `blake2b` | **46.556** | 67.316 | 71.705 | n/a | n/a |
| `sha512` | **50.080** | 50.168 | 52.158 | n/a | n/a |
| `x25519` | **35.049** | 51.784 | 52.087 | n/a | n/a |

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
| _(floor: empty program)_ | _7.326_ | _128.167_ | _**135.493**_ | _69.234_ | _84.970_ | _70.014_ |
| `lcg` | 7.170 | 138.035 | **145.205** | 67.851 | 96.080 | 74.689 |
| `packet_classifier` | 7.249 | 139.591 | **146.840** | 68.105 | 97.031 | 75.972 |
| `ring_write` | 15.948 | 141.749 | **157.697** | 77.525 | 98.327 | 78.498 |
| `histogram_bins` | 16.361 | 145.200 | **161.561** | 78.820 | 143.903 | 83.609 |
| `prefix_scan` | 16.095 | 144.198 | **160.293** | 78.152 | 104.626 | 81.388 |
| `binary_search` | 16.377 | 142.312 | **158.689** | 77.578 | 100.633 | 81.870 |
| `sort_window` | 16.584 | 145.374 | **161.958** | 78.434 | 111.402 | 90.548 |
| `bloom_filter` | 17.335 | 146.788 | **164.123** | 78.485 | 108.905 | 83.256 |
| `hash_join` | 20.612 | 281.213 | **301.825** | 82.419 | 229.014 | 130.972 |
| `sieve` | 15.886 | 142.505 | **158.391** | 78.668 | 110.368 | 87.565 |
| `fib` | 7.176 | 132.131 | **139.307** | 64.501 | 93.089 | 75.778 |
| `collatz` | 7.356 | 143.718 | **151.074** | 69.091 | 100.107 | 77.781 |
| `matmul` | 17.075 | 148.772 | **165.847** | 80.426 | 117.947 | 100.858 |
| `json_parse` | 48.794 | 359.704 | **408.498** | 112.731 | 172.188 | 182.018 |
| `nbody` | 18.790 | 153.927 | **172.717** | 82.990 | 140.126 | 121.003 |
| `chacha20` | 70.997 | 726.855 | **797.852** | 134.518 | 154.944 | 130.288 |
| `poly1305` | 58.708 | 440.990 | **499.698** | 123.343 | 157.232 | 146.454 |
| `blake2b` | 39.145 | 358.779 | **397.924** | 103.910 | 156.595 | 139.177 |
| `sha512` | 37.963 | 478.454 | **516.417** | 101.859 | 147.690 | 122.943 |
| `x25519` | 54.954 | 1449.091 | **1504.045** | 117.561 | 1277.043 | 528.302 |

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
