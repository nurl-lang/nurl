# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T18:07:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b217f54463c4646146a7872afdaf22cc59179cbb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40927049161 |
| NURL | `v0.80.0-69-gb217f544` |
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
| _(floor: empty program)_ | _1.261_ | _1.215_ | _1.366_ | _18.832_ | _13.238_ |
| `lcg` | 29.828 | **29.776** | 29.807 | 1107.847 | 2984.564 |
| `packet_classifier` | 41.307 | 41.890 | **40.709** | 131.771 | 2554.699 |
| `ring_write` | 29.857 | **28.417** | 29.382 | 51.969 | 3575.193 |
| `histogram_bins` | **28.059** | 28.074 | 29.365 | 50.609 | 3368.937 |
| `prefix_scan` | **16.206** | 16.290 | 16.470 | 47.328 | 2609.087 |
| `binary_search` | 14.859 | **14.644** | 15.540 | 69.736 | 3754.012 |
| `sort_window` | 19.600 | **19.416** | 19.725 | 133.424 | 6591.855 |
| `bloom_filter` | **8.539** | 8.624 | 8.648 | 1597.405 | 4353.545 |
| `hash_join` | **16.242** | 16.620 | 17.402 | 1896.589 | 4727.398 |
| `sieve` | 15.797 | 15.370 | **15.368** | 49.314 | 1688.421 |
| `fib` | 19.285 | 19.265 | **19.015** | 73.538 | 676.164 |
| `collatz` | 9.503 | 9.073 | **9.041** | 35.570 | 407.107 |
| `matmul` | **19.736** | 20.815 | 20.554 | 52.193 | 1752.668 |
| `json_parse` | **5.005** | 5.577 | 6.975 | 25.332 | 23.683 |
| `nbody` | **16.152** | 23.847 | 16.874 | 59.063 | 1568.524 |
| `chacha20` | **6.630** | 19.367 | 18.663 | n/a | n/a |
| `poly1305` | **8.389** | 25.775 | 15.020 | n/a | n/a |
| `blake2b` | **25.513** | 41.081 | 47.138 | n/a | n/a |
| `sha512` | **29.165** | 32.740 | 30.920 | n/a | n/a |
| `x25519` | **18.958** | 30.059 | 31.127 | n/a | n/a |

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
| _(floor: empty program)_ | _3.834_ | _94.958_ | _**98.792**_ | _60.680_ | _78.534_ | _55.087_ |
| `lcg` | 3.934 | 108.050 | **111.984** | 54.576 | 80.816 | 59.832 |
| `packet_classifier` | 3.858 | 104.322 | **108.180** | 52.593 | 78.054 | 60.945 |
| `ring_write` | 10.964 | 105.869 | **116.833** | 58.749 | 79.374 | 60.786 |
| `histogram_bins` | 10.432 | 99.597 | **110.029** | 56.256 | 84.171 | 63.474 |
| `prefix_scan` | 10.604 | 102.399 | **113.003** | 56.780 | 78.271 | 60.701 |
| `binary_search` | 10.928 | 102.256 | **113.184** | 57.138 | 77.536 | 62.607 |
| `sort_window` | 10.772 | 102.195 | **112.967** | 57.067 | 85.258 | 68.395 |
| `bloom_filter` | 10.878 | 102.787 | **113.665** | 56.219 | 81.081 | 63.656 |
| `hash_join` | 12.687 | 171.993 | **184.680** | 57.514 | 143.063 | 95.527 |
| `sieve` | 10.332 | 103.538 | **113.870** | 56.030 | 83.954 | 68.878 |
| `fib` | 3.709 | 96.974 | **100.683** | 51.247 | 73.938 | 55.995 |
| `collatz` | 3.878 | 97.731 | **101.609** | 50.047 | 73.308 | 57.537 |
| `matmul` | 11.370 | 101.138 | **112.508** | 56.489 | 85.378 | 73.471 |
| `json_parse` | 30.070 | 285.562 | **315.632** | 75.771 | 117.351 | 126.697 |
| `nbody` | 11.508 | 102.794 | **114.302** | 56.999 | 95.353 | 80.506 |
| `chacha20` | 32.441 | 450.316 | **482.757** | 76.737 | 99.336 | 130.373 |
| `poly1305` | 26.011 | 327.287 | **353.298** | 71.348 | 103.830 | 99.155 |
| `blake2b` | 23.523 | 246.074 | **269.597** | 80.794 | 104.869 | 97.578 |
| `sha512` | 23.859 | 289.580 | **313.439** | 67.822 | 103.923 | 89.365 |
| `x25519` | 30.620 | 736.853 | **767.473** | 75.627 | 713.858 | 319.274 |

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
