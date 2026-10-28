# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T20:11:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e9fee615ca09dd8f78c7e1f209680455572a9f14` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40760303804 |
| NURL | `v0.80.0-11-ge9fee615` |
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
| _(floor: empty program)_ | _1.275_ | _1.263_ | _1.408_ | _19.958_ | _13.767_ |
| `lcg` | 29.863 | **29.687** | 29.897 | 1131.048 | 2984.335 |
| `packet_classifier` | 43.362 | 43.349 | **43.121** | 134.922 | 2766.156 |
| `ring_write` | 30.197 | **30.162** | 30.548 | 53.408 | 3738.627 |
| `histogram_bins` | 30.420 | 30.426 | **30.400** | 52.917 | 3654.964 |
| `prefix_scan` | 16.844 | **16.754** | 17.123 | 52.063 | 2549.742 |
| `binary_search` | **15.482** | 15.683 | 16.234 | 73.750 | 3912.459 |
| `sort_window` | 21.338 | **21.186** | 21.267 | 139.085 | 6400.608 |
| `bloom_filter` | **9.141** | 9.208 | 9.470 | 1675.274 | 4554.389 |
| `hash_join` | **16.905** | 17.721 | 18.756 | 2013.544 | 4688.546 |
| `sieve` | 16.119 | **15.321** | 15.620 | 52.313 | 1935.478 |
| `fib` | 20.143 | **20.129** | 20.667 | 81.268 | 710.237 |
| `collatz` | 10.005 | **9.900** | 10.094 | 41.172 | 427.818 |
| `matmul` | **21.282** | 21.730 | 21.894 | 58.729 | 1759.650 |
| `json_parse` | **5.372** | 5.782 | 7.563 | 28.504 | 26.963 |
| `nbody` | 20.878 | 26.337 | **18.396** | 67.117 | 1533.989 |
| `chacha20` | **6.884** | 20.327 | 19.754 | n/a | n/a |
| `poly1305` | **8.935** | 27.312 | 15.946 | n/a | n/a |
| `blake2b` | **27.548** | 45.574 | 50.743 | n/a | n/a |
| `sha512` | **31.163** | 34.030 | 33.285 | n/a | n/a |
| `x25519` | **20.943** | 31.340 | 31.753 | n/a | n/a |

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
| _(floor: empty program)_ | _3.838_ | _100.848_ | _**104.686**_ | _56.463_ | _79.069_ | _56.565_ |
| `lcg` | 3.961 | 113.305 | **117.266** | 55.546 | 81.882 | 64.167 |
| `packet_classifier` | 4.262 | 114.132 | **118.394** | 58.851 | 85.366 | 62.546 |
| `ring_write` | 11.712 | 113.151 | **124.863** | 63.440 | 92.831 | 68.435 |
| `histogram_bins` | 11.329 | 112.820 | **124.149** | 63.557 | 97.260 | 73.293 |
| `prefix_scan` | 11.834 | 118.096 | **129.930** | 65.915 | 90.811 | 68.040 |
| `binary_search` | 11.616 | 113.845 | **125.461** | 64.668 | 89.102 | 67.636 |
| `sort_window` | 11.483 | 115.933 | **127.416** | 64.596 | 95.549 | 74.353 |
| `bloom_filter` | 11.693 | 112.318 | **124.011** | 63.679 | 90.842 | 73.862 |
| `hash_join` | 14.140 | 192.047 | **206.187** | 65.278 | 157.427 | 102.612 |
| `sieve` | 11.628 | 111.721 | **123.349** | 63.258 | 92.687 | 73.574 |
| `fib` | 4.546 | 113.155 | **117.701** | 58.527 | 86.950 | 64.950 |
| `collatz` | 4.656 | 113.408 | **118.064** | 58.407 | 86.489 | 65.806 |
| `matmul` | 12.086 | 111.763 | **123.849** | 63.792 | 94.882 | 83.300 |
| `json_parse` | 33.093 | 335.339 | **368.432** | 86.153 | 130.688 | 143.666 |
| `nbody` | 13.098 | 119.540 | **132.638** | 66.021 | 107.606 | 92.855 |
| `chacha20` | 37.544 | 529.713 | **567.257** | 89.576 | 114.231 | 102.298 |
| `poly1305` | 28.007 | 358.171 | **386.178** | 77.048 | 112.813 | 113.718 |
| `blake2b` | 26.862 | 263.834 | **290.696** | 80.313 | 136.166 | 112.088 |
| `sha512` | 26.376 | 326.049 | **352.425** | 78.792 | 114.708 | 99.439 |
| `x25519` | 36.683 | 753.615 | **790.298** | 87.006 | 776.279 | 346.094 |

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
