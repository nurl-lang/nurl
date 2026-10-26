# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T15:00:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3fd99388b4ab5fb41802bc3f1bfe4621ef5a9c9a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40343937856 |
| NURL | `v0.78.0-26-g3fd99388` |
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
| _(floor: empty program)_ | _1.569_ | _1.535_ | _1.775_ | _25.992_ | _18.858_ |
| `lcg` | 45.036 | **45.018** | 45.188 | 1867.599 | 5588.550 |
| `packet_classifier` | 64.831 | **64.779** | 64.961 | 161.840 | 4630.660 |
| `ring_write` | 48.706 | **48.674** | 48.898 | 77.713 | 6651.531 |
| `histogram_bins` | 45.528 | **45.511** | 45.775 | 77.549 | 6684.932 |
| `prefix_scan` | 24.993 | **24.972** | 25.165 | 74.040 | 4812.413 |
| `binary_search` | 36.949 | **36.402** | 44.317 | 115.088 | 6884.624 |
| `sort_window` | 30.541 | **30.493** | 30.897 | 171.054 | 11328.170 |
| `bloom_filter` | **17.667** | 19.094 | 21.117 | 2816.432 | 8086.376 |
| `hash_join` | **28.351** | 29.364 | 30.815 | 3432.083 | 8552.579 |
| `sieve` | 20.879 | **20.463** | 20.586 | 72.722 | 3735.042 |
| `fib` | 33.882 | **33.782** | 33.988 | 145.317 | 1313.967 |
| `collatz` | 14.015 | **13.998** | 14.351 | 55.269 | 765.156 |
| `matmul` | 47.102 | **46.676** | 47.193 | 86.725 | 3348.887 |
| `json_parse` | **8.028** | 8.880 | 12.273 | 39.522 | 40.488 |
| `nbody` | **26.704** | 45.043 | 26.882 | 96.748 | 3229.073 |
| `chacha20` | **8.590** | 46.043 | 35.645 | n/a | n/a |
| `poly1305` | **12.693** | 40.332 | 24.009 | n/a | n/a |
| `blake2b` | **48.664** | 71.662 | 78.606 | n/a | n/a |
| `sha512` | **49.950** | 51.858 | 54.722 | n/a | n/a |
| `x25519` | **49.151** | 54.192 | 55.968 | n/a | n/a |

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
| _(floor: empty program)_ | _4.920_ | _127.327_ | _**132.247**_ | _69.683_ | _91.754_ | _56.661_ |
| `lcg` | 5.108 | 136.964 | **142.072** | 70.041 | 101.747 | 62.739 |
| `packet_classifier` | 5.065 | 136.746 | **141.811** | 69.490 | 102.003 | 63.531 |
| `ring_write` | 16.427 | 140.938 | **157.365** | 81.302 | 103.101 | 65.446 |
| `histogram_bins` | 16.602 | 141.931 | **158.533** | 82.187 | 119.008 | 73.865 |
| `prefix_scan` | 16.725 | 141.545 | **158.270** | 81.821 | 108.638 | 68.214 |
| `binary_search` | 16.844 | 140.050 | **156.894** | 82.375 | 108.272 | 69.508 |
| `sort_window` | 17.108 | 143.667 | **160.775** | 82.680 | 116.626 | 72.870 |
| `bloom_filter` | 17.480 | 145.809 | **163.289** | 84.884 | 112.061 | 71.009 |
| `hash_join` | 21.591 | 278.430 | **300.021** | 87.292 | 220.023 | 117.431 |
| `sieve` | 16.937 | 142.729 | **159.666** | 83.318 | 114.227 | 76.918 |
| `fib` | 5.379 | 137.460 | **142.839** | 69.662 | 101.153 | 64.956 |
| `collatz` | 5.480 | 141.537 | **147.017** | 70.990 | 104.688 | 65.379 |
| `matmul` | 18.243 | 142.312 | **160.555** | 82.714 | 117.675 | 84.974 |
| `json_parse` | 51.517 | 481.750 | **533.267** | 118.320 | 167.946 | 163.491 |
| `nbody` | 19.285 | 147.944 | **167.229** | 84.739 | 136.209 | 100.223 |
| `chacha20` | 58.786 | 806.468 | **865.254** | 122.641 | 148.174 | 110.421 |
| `poly1305` | 44.048 | 511.395 | **555.443** | 109.031 | 149.538 | 125.606 |
| `blake2b` | 41.881 | 387.697 | **429.578** | 108.773 | 156.796 | 122.446 |
| `sha512` | 41.095 | 476.827 | **517.922** | 107.539 | 149.133 | 109.169 |
| `x25519` | 41.044 | 825.186 | **866.230** | 108.500 | 1217.111 | 502.113 |

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
