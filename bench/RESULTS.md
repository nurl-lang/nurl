# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T15:24:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `4b3e18fb5587d5078fc323f8d095933dd007f350` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40900358690 |
| NURL | `v0.80.0-65-g4b3e18fb` |
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
| _(floor: empty program)_ | _1.308_ | _1.291_ | _1.490_ | _19.163_ | _13.779_ |
| `lcg` | 30.710 | **30.042** | 30.899 | 1133.603 | 2996.682 |
| `packet_classifier` | 43.036 | **43.030** | 43.345 | 136.516 | 2699.984 |
| `ring_write` | 30.245 | 30.168 | **30.063** | 53.917 | 3868.188 |
| `histogram_bins` | 30.199 | **29.802** | 30.167 | 53.065 | 3422.735 |
| `prefix_scan` | 16.864 | **16.733** | 16.881 | 51.421 | 2642.233 |
| `binary_search` | 15.449 | **15.428** | 16.367 | 73.488 | 3661.340 |
| `sort_window` | 21.084 | 20.730 | **20.299** | 141.618 | 6802.485 |
| `bloom_filter` | **9.413** | 11.898 | 9.643 | 1690.353 | 4518.614 |
| `hash_join` | **16.542** | 17.193 | 18.681 | 2022.872 | 4625.543 |
| `sieve` | 16.338 | **15.877** | 16.056 | 52.009 | 1905.243 |
| `fib` | **19.990** | 19.991 | 20.030 | 81.293 | 692.988 |
| `collatz` | 9.529 | **9.427** | 9.879 | 40.907 | 426.082 |
| `matmul` | 24.971 | 21.833 | **21.569** | 57.915 | 1794.975 |
| `json_parse` | **5.431** | 5.925 | 7.299 | 28.598 | 28.812 |
| `nbody` | **17.419** | 25.692 | 18.212 | 68.416 | 1517.000 |
| `chacha20` | **6.999** | 20.274 | 19.983 | n/a | n/a |
| `poly1305` | **9.179** | 27.525 | 16.317 | n/a | n/a |
| `blake2b` | **26.843** | 43.162 | 48.829 | n/a | n/a |
| `sha512` | **30.718** | 33.293 | 31.861 | n/a | n/a |
| `x25519` | **19.880** | 31.175 | 31.690 | n/a | n/a |

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
| _(floor: empty program)_ | _4.036_ | _101.605_ | _**105.641**_ | _55.997_ | _74.688_ | _54.974_ |
| `lcg` | 3.939 | 106.628 | **110.567** | 55.147 | 81.370 | 62.192 |
| `packet_classifier` | 4.380 | 112.760 | **117.140** | 57.183 | 85.578 | 67.499 |
| `ring_write` | 11.798 | 112.427 | **124.225** | 62.712 | 86.277 | 66.400 |
| `histogram_bins` | 11.686 | 113.527 | **125.213** | 63.348 | 94.858 | 71.667 |
| `prefix_scan` | 11.757 | 110.186 | **121.943** | 61.683 | 90.835 | 69.360 |
| `binary_search` | 12.182 | 115.316 | **127.498** | 65.203 | 95.204 | 78.249 |
| `sort_window` | 11.798 | 113.196 | **124.994** | 63.729 | 92.134 | 71.910 |
| `bloom_filter` | 12.624 | 115.463 | **128.087** | 65.987 | 93.544 | 71.352 |
| `hash_join` | 13.869 | 187.361 | **201.230** | 64.857 | 156.594 | 109.082 |
| `sieve` | 11.016 | 109.992 | **121.008** | 61.404 | 91.266 | 76.765 |
| `fib` | 4.231 | 108.576 | **112.807** | 54.763 | 85.201 | 64.393 |
| `collatz` | 4.270 | 110.971 | **115.241** | 55.544 | 84.765 | 66.186 |
| `matmul` | 12.097 | 114.864 | **126.961** | 62.493 | 94.800 | 85.654 |
| `json_parse` | 33.511 | 337.101 | **370.612** | 88.386 | 129.555 | 150.127 |
| `nbody` | 13.387 | 115.017 | **128.404** | 64.187 | 109.169 | 93.148 |
| `chacha20` | 36.752 | 515.064 | **551.816** | 88.183 | 114.914 | 100.317 |
| `poly1305` | 29.565 | 353.921 | **383.486** | 80.482 | 113.878 | 113.794 |
| `blake2b` | 27.530 | 265.896 | **293.426** | 80.034 | 131.552 | 108.410 |
| `sha512` | 26.126 | 323.230 | **349.356** | 76.770 | 114.669 | 103.699 |
| `x25519` | 36.819 | 843.648 | **880.467** | 89.739 | 795.669 | 348.575 |

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
