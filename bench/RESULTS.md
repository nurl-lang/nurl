# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T04:14:15Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c6803f447d521f4853d5d0b0214b45007ee96dcf` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41001300853 |
| NURL | `v0.80.0-105-gc6803f44` |
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
| _(floor: empty program)_ | _1.187_ | _1.129_ | _1.315_ | _15.991_ | _11.285_ |
| `lcg` | 27.851 | **27.824** | 27.875 | 1064.981 | 2827.789 |
| `packet_classifier` | 42.008 | 41.244 | **40.441** | 123.636 | 2580.656 |
| `ring_write` | 27.903 | **27.803** | 28.130 | 46.733 | 3476.753 |
| `histogram_bins` | **27.768** | 27.811 | 27.935 | 48.443 | 3325.709 |
| `prefix_scan` | 15.504 | **15.456** | 15.561 | 46.743 | 2432.955 |
| `binary_search` | 14.159 | **13.972** | 14.777 | 65.306 | 3549.816 |
| `sort_window` | 19.539 | **19.337** | 19.498 | 127.906 | 6022.963 |
| `bloom_filter` | **8.571** | 8.817 | 8.951 | 1556.464 | 4275.247 |
| `hash_join` | **15.493** | 16.177 | 17.248 | 1858.834 | 4336.103 |
| `sieve` | 14.575 | 14.265 | **14.251** | 45.695 | 1818.332 |
| `fib` | 18.511 | 18.518 | **18.403** | 71.788 | 645.870 |
| `collatz` | 8.985 | **8.870** | 9.095 | 34.532 | 400.150 |
| `matmul` | **19.524** | 19.765 | 19.832 | 50.699 | 1708.766 |
| `json_parse` | **4.735** | 5.219 | 6.722 | 23.489 | 23.786 |
| `nbody` | 16.656 | 23.721 | **16.477** | 55.257 | 1437.303 |
| `chacha20` | **6.470** | 18.924 | 18.441 | n/a | n/a |
| `poly1305` | **8.509** | 25.606 | 14.897 | n/a | n/a |
| `blake2b` | **24.927** | 40.392 | 45.599 | n/a | n/a |
| `sha512` | **28.765** | 31.410 | 30.682 | n/a | n/a |
| `x25519` | **18.384** | 28.905 | 29.535 | n/a | n/a |

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
| _(floor: empty program)_ | _3.678_ | _89.970_ | _**93.648**_ | _50.661_ | _62.838_ | _48.102_ |
| `lcg` | 3.564 | 93.272 | **96.836** | 47.794 | 71.645 | 54.443 |
| `packet_classifier` | 3.584 | 93.733 | **97.317** | 48.220 | 71.252 | 58.584 |
| `ring_write` | 10.058 | 97.688 | **107.746** | 54.514 | 73.390 | 58.845 |
| `histogram_bins` | 10.058 | 96.577 | **106.635** | 54.100 | 82.052 | 60.349 |
| `prefix_scan` | 10.333 | 96.030 | **106.363** | 54.685 | 77.619 | 59.649 |
| `binary_search` | 10.274 | 94.164 | **104.438** | 55.329 | 81.727 | 58.956 |
| `sort_window` | 10.666 | 97.085 | **107.751** | 54.162 | 79.226 | 62.348 |
| `bloom_filter` | 10.971 | 99.171 | **110.142** | 56.292 | 82.531 | 63.275 |
| `hash_join` | 12.259 | 162.817 | **175.076** | 55.092 | 138.038 | 90.250 |
| `sieve` | 10.157 | 94.845 | **105.002** | 53.225 | 77.588 | 65.353 |
| `fib` | 3.716 | 92.187 | **95.903** | 47.894 | 70.596 | 56.167 |
| `collatz` | 3.762 | 94.455 | **98.217** | 48.155 | 69.957 | 55.670 |
| `matmul` | 10.737 | 95.666 | **106.403** | 55.171 | 78.992 | 71.071 |
| `json_parse` | 29.437 | 282.859 | **312.296** | 73.200 | 119.405 | 185.347 |
| `nbody` | 11.415 | 99.003 | **110.418** | 55.192 | 93.244 | 78.691 |
| `chacha20` | 32.130 | 447.693 | **479.823** | 76.996 | 98.913 | 87.566 |
| `poly1305` | 24.853 | 306.748 | **331.601** | 68.643 | 99.107 | 97.161 |
| `blake2b` | 23.354 | 228.883 | **252.237** | 67.328 | 103.137 | 94.508 |
| `sha512` | 22.814 | 280.407 | **303.221** | 66.139 | 97.313 | 87.233 |
| `x25519` | 29.847 | 724.198 | **754.045** | 73.488 | 700.697 | 314.672 |

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
