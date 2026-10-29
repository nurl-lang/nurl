# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T05:53:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `adac93f2392272ed1868f82a241bc55f046b8020` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40825424811 |
| NURL | `v0.80.0-40-gadac93f2` |
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
| _(floor: empty program)_ | _1.521_ | _1.503_ | _1.741_ | _24.135_ | _17.118_ |
| `lcg` | 39.172 | **39.161** | 39.467 | 1816.351 | 5031.637 |
| `packet_classifier` | **56.184** | 56.251 | 56.804 | 161.893 | 4327.231 |
| `ring_write` | 42.277 | **42.236** | 42.493 | 67.047 | 6317.939 |
| `histogram_bins` | **39.648** | 40.698 | 40.750 | 67.552 | 6122.578 |
| `prefix_scan` | 21.802 | **21.701** | 21.971 | 65.887 | 4662.592 |
| `binary_search` | 39.677 | **38.280** | 40.933 | 106.473 | 6253.407 |
| `sort_window` | 26.703 | **26.668** | 26.886 | 198.165 | 11507.026 |
| `bloom_filter` | **16.685** | 17.933 | 18.472 | 2858.524 | 7719.683 |
| `hash_join` | **26.802** | 27.942 | 29.271 | 3479.190 | 8240.349 |
| `sieve` | 24.746 | **23.529** | 23.776 | 70.935 | 3263.507 |
| `fib` | **25.060** | 29.921 | 30.088 | 131.740 | 1369.373 |
| `collatz` | **12.271** | 12.345 | 12.511 | 50.383 | 741.932 |
| `matmul` | 33.640 | **33.508** | 33.807 | 78.018 | 3122.324 |
| `json_parse` | **8.406** | 8.690 | 11.793 | 36.821 | 38.998 |
| `nbody` | **25.183** | 39.797 | 25.391 | 100.863 | 3152.455 |
| `chacha20` | **7.288** | 42.015 | 33.601 | n/a | n/a |
| `poly1305` | **11.754** | 31.854 | 21.209 | n/a | n/a |
| `blake2b` | **44.130** | 65.035 | 69.005 | n/a | n/a |
| `sha512` | **47.357** | 50.561 | 49.533 | n/a | n/a |
| `x25519` | **31.645** | 48.655 | 49.293 | n/a | n/a |

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
| _(floor: empty program)_ | _4.755_ | _126.839_ | _**131.594**_ | _63.759_ | _83.971_ | _63.347_ |
| `lcg` | 4.862 | 129.628 | **134.490** | 64.104 | 92.529 | 70.535 |
| `packet_classifier` | 4.843 | 130.546 | **135.389** | 64.060 | 93.500 | 72.257 |
| `ring_write` | 15.397 | 133.288 | **148.685** | 74.027 | 95.166 | 74.955 |
| `histogram_bins` | 15.696 | 133.881 | **149.577** | 74.422 | 112.094 | 87.825 |
| `prefix_scan` | 15.871 | 136.606 | **152.477** | 74.889 | 99.818 | 75.534 |
| `binary_search` | 15.909 | 132.997 | **148.906** | 76.946 | 98.623 | 78.048 |
| `sort_window` | 15.682 | 134.695 | **150.377** | 73.816 | 105.993 | 82.609 |
| `bloom_filter` | 16.351 | 135.636 | **151.987** | 74.675 | 105.222 | 78.362 |
| `hash_join` | 19.902 | 267.075 | **286.977** | 78.100 | 227.409 | 127.418 |
| `sieve` | 15.870 | 132.042 | **147.912** | 74.511 | 106.371 | 84.530 |
| `fib` | 4.976 | 131.592 | **136.568** | 64.591 | 94.469 | 71.768 |
| `collatz` | 5.130 | 135.864 | **140.994** | 66.204 | 96.469 | 72.002 |
| `matmul` | 17.501 | 134.761 | **152.262** | 76.500 | 109.893 | 93.858 |
| `json_parse` | 50.807 | 477.852 | **528.659** | 111.768 | 165.422 | 176.014 |
| `nbody` | 18.605 | 141.122 | **159.727** | 77.793 | 130.107 | 109.975 |
| `chacha20` | 58.066 | 759.826 | **817.892** | 117.140 | 144.657 | 121.564 |
| `poly1305` | 44.085 | 515.333 | **559.418** | 103.747 | 145.040 | 137.788 |
| `blake2b` | 39.350 | 383.316 | **422.666** | 99.662 | 149.653 | 135.397 |
| `sha512` | 39.723 | 476.790 | **516.513** | 98.613 | 142.109 | 117.508 |
| `x25519` | 53.914 | 1293.665 | **1347.579** | 113.167 | 1222.771 | 515.856 |

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
