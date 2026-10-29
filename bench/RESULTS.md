# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T03:16:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `60e27cade821d915c6df7ca840cd925860a91c7f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40810752325 |
| NURL | `v0.80.0-27-g60e27cad` |
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
| _(floor: empty program)_ | _1.292_ | _1.242_ | _1.400_ | _20.185_ | _12.629_ |
| `lcg` | 30.025 | **29.682** | 30.177 | 1146.695 | 2976.023 |
| `packet_classifier` | **42.363** | 42.412 | 42.672 | 134.419 | 2810.896 |
| `ring_write` | 28.946 | **28.623** | 29.750 | 52.135 | 3620.733 |
| `histogram_bins` | **29.852** | 30.505 | 30.191 | 52.554 | 3531.090 |
| `prefix_scan` | 16.440 | **16.426** | 16.738 | 49.767 | 2614.901 |
| `binary_search` | 15.393 | **15.005** | 15.525 | 70.912 | 3625.659 |
| `sort_window` | 20.965 | **20.804** | 20.973 | 136.300 | 6558.715 |
| `bloom_filter` | **8.605** | 8.620 | 8.740 | 1629.177 | 4490.703 |
| `hash_join` | **16.578** | 17.058 | 18.016 | 1989.291 | 4655.229 |
| `sieve` | 16.204 | 15.822 | **14.805** | 47.575 | 1890.873 |
| `fib` | 19.979 | **19.802** | 19.832 | 78.035 | 680.368 |
| `collatz` | 10.416 | **9.580** | 9.696 | 39.768 | 418.961 |
| `matmul` | 21.187 | **21.145** | 21.181 | 55.024 | 1820.421 |
| `json_parse` | **5.081** | 5.523 | 7.069 | 26.936 | 26.224 |
| `nbody` | 17.028 | 24.606 | **16.629** | 61.582 | 1484.450 |
| `chacha20` | **6.883** | 20.098 | 19.486 | n/a | n/a |
| `poly1305` | **8.745** | 26.945 | 15.647 | n/a | n/a |
| `blake2b` | **26.478** | 43.194 | 48.993 | n/a | n/a |
| `sha512` | 33.182 | 33.528 | **32.935** | n/a | n/a |
| `x25519` | **19.389** | 29.449 | 30.047 | n/a | n/a |

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
| _(floor: empty program)_ | _3.679_ | _93.921_ | _**97.600**_ | _52.803_ | _73.045_ | _53.361_ |
| `lcg` | 4.010 | 107.548 | **111.558** | 54.313 | 78.522 | 88.037 |
| `packet_classifier` | 4.051 | 106.860 | **110.911** | 53.861 | 85.973 | 60.713 |
| `ring_write` | 11.007 | 106.467 | **117.474** | 60.972 | 81.636 | 63.345 |
| `histogram_bins` | 11.075 | 109.725 | **120.800** | 61.186 | 92.984 | 69.031 |
| `prefix_scan` | 11.406 | 111.721 | **123.127** | 62.606 | 87.721 | 67.964 |
| `binary_search` | 11.054 | 103.349 | **114.403** | 59.610 | 81.582 | 64.724 |
| `sort_window` | 11.116 | 105.030 | **116.146** | 57.350 | 88.452 | 70.309 |
| `bloom_filter` | 11.001 | 103.099 | **114.100** | 57.279 | 82.950 | 65.346 |
| `hash_join` | 13.331 | 181.218 | **194.549** | 61.008 | 148.508 | 96.721 |
| `sieve` | 11.020 | 100.893 | **111.913** | 58.177 | 84.463 | 77.991 |
| `fib` | 3.988 | 104.205 | **108.193** | 53.015 | 76.896 | 60.480 |
| `collatz` | 4.116 | 102.994 | **107.110** | 52.403 | 79.463 | 60.074 |
| `matmul` | 11.250 | 104.531 | **115.781** | 58.982 | 85.243 | 81.701 |
| `json_parse` | 32.673 | 318.150 | **350.823** | 83.475 | 121.417 | 140.557 |
| `nbody` | 12.476 | 108.627 | **121.103** | 61.143 | 99.060 | 85.607 |
| `chacha20` | 34.285 | 472.944 | **507.229** | 82.470 | 113.422 | 140.011 |
| `poly1305` | 27.133 | 330.326 | **357.459** | 75.530 | 108.727 | 108.337 |
| `blake2b` | 25.071 | 247.101 | **272.172** | 73.809 | 116.063 | 103.673 |
| `sha512` | 25.331 | 305.760 | **331.091** | 73.094 | 106.829 | 94.567 |
| `x25519` | 32.999 | 793.066 | **826.065** | 82.068 | 754.948 | 336.009 |

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
