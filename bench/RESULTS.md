# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T01:18:10Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `3da86da1cd0485cb9b50116d7db6e992c3938a4b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40984362216 |
| NURL | `v0.80.0-90-g3da86da1` |
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
| _(floor: empty program)_ | _1.642_ | _1.624_ | _1.853_ | _25.391_ | _18.021_ |
| `lcg` | **44.114** | 44.193 | 44.391 | 1833.412 | 5482.744 |
| `packet_classifier` | **63.562** | 63.609 | 63.800 | 159.441 | 4599.033 |
| `ring_write` | 47.704 | **47.698** | 47.890 | 74.681 | 6605.707 |
| `histogram_bins` | 44.742 | **44.661** | 44.859 | 76.020 | 6299.517 |
| `prefix_scan` | 24.546 | **24.490** | 24.675 | 72.915 | 4617.738 |
| `binary_search` | 41.486 | **35.759** | 43.530 | 112.612 | 6801.766 |
| `sort_window` | 30.120 | **30.063** | 30.277 | 167.429 | 11276.680 |
| `bloom_filter` | **17.402** | 18.831 | 20.704 | 2783.758 | 7672.391 |
| `hash_join` | **27.816** | 28.706 | 30.198 | 3455.101 | 8658.007 |
| `sieve` | 25.244 | 24.163 | **24.081** | 74.168 | 3468.462 |
| `fib` | **28.014** | 33.207 | 33.451 | 143.462 | 1299.092 |
| `collatz` | 13.776 | **13.728** | 14.039 | 52.857 | 756.887 |
| `matmul` | 45.776 | 45.689 | **44.862** | 84.782 | 3486.324 |
| `json_parse` | **8.090** | 9.004 | 12.204 | 39.974 | 39.976 |
| `nbody` | **26.824** | 45.069 | 26.920 | 97.228 | 3334.943 |
| `chacha20` | **8.680** | 46.250 | 35.733 | n/a | n/a |
| `poly1305` | **12.748** | 40.222 | 23.852 | n/a | n/a |
| `blake2b` | **49.454** | 71.952 | 78.235 | n/a | n/a |
| `sha512` | **49.726** | 51.934 | 54.590 | n/a | n/a |
| `x25519` | **35.727** | 54.228 | 56.035 | n/a | n/a |

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
| _(floor: empty program)_ | _5.371_ | _127.402_ | _**132.773**_ | _72.628_ | _93.588_ | _68.705_ |
| `lcg` | 5.398 | 138.790 | **144.188** | 70.818 | 100.690 | 88.877 |
| `packet_classifier` | 5.629 | 139.445 | **145.074** | 72.009 | 102.286 | 77.698 |
| `ring_write` | 16.352 | 139.642 | **155.994** | 80.269 | 103.046 | 78.247 |
| `histogram_bins` | 16.594 | 144.591 | **161.185** | 82.266 | 120.714 | 87.094 |
| `prefix_scan` | 16.745 | 141.186 | **157.931** | 81.267 | 107.936 | 81.668 |
| `binary_search` | 16.732 | 141.779 | **158.511** | 81.461 | 106.088 | 84.511 |
| `sort_window` | 16.923 | 144.644 | **161.567** | 82.107 | 114.708 | 89.140 |
| `bloom_filter` | 17.363 | 145.459 | **162.822** | 82.249 | 113.532 | 85.886 |
| `hash_join` | 20.811 | 268.988 | **289.799** | 86.741 | 221.857 | 133.002 |
| `sieve` | 16.782 | 139.960 | **156.742** | 81.186 | 112.441 | 92.823 |
| `fib` | 5.563 | 138.657 | **144.220** | 71.399 | 101.222 | 77.970 |
| `collatz` | 5.610 | 141.708 | **147.318** | 71.703 | 102.374 | 78.606 |
| `matmul` | 17.957 | 141.253 | **159.210** | 82.219 | 115.086 | 101.043 |
| `json_parse` | 51.742 | 461.590 | **513.332** | 118.810 | 167.253 | 182.645 |
| `nbody` | 19.520 | 146.898 | **166.418** | 83.645 | 136.136 | 116.194 |
| `chacha20` | 58.255 | 740.051 | **798.306** | 124.207 | 148.864 | 129.355 |
| `poly1305` | 44.861 | 509.637 | **554.498** | 111.009 | 150.243 | 142.687 |
| `blake2b` | 40.325 | 373.740 | **414.065** | 106.502 | 154.705 | 140.441 |
| `sha512` | 40.117 | 462.497 | **502.614** | 105.240 | 146.916 | 126.590 |
| `x25519` | 53.922 | 1249.080 | **1303.002** | 120.080 | 1198.842 | 520.012 |

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
