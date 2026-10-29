# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T10:51:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `59ac976798fcf939efbeed9127a910aabdb0e943` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40859994521 |
| NURL | `v0.80.0-53-g59ac9767` |
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
| _(floor: empty program)_ | _1.585_ | _1.529_ | _1.762_ | _25.116_ | _18.789_ |
| `lcg` | 39.435 | **39.352** | 39.537 | 1827.081 | 5257.834 |
| `packet_classifier` | 56.481 | **56.418** | 56.726 | 164.377 | 4346.021 |
| `ring_write` | **42.532** | 42.553 | 42.705 | 67.836 | 6700.991 |
| `histogram_bins` | **40.573** | 40.809 | 41.088 | 67.185 | 6105.540 |
| `prefix_scan` | **21.763** | 21.800 | 21.990 | 67.028 | 4636.355 |
| `binary_search` | 39.768 | **38.496** | 41.235 | 109.514 | 6477.499 |
| `sort_window` | 26.881 | **26.858** | 27.021 | 199.961 | 13639.949 |
| `bloom_filter` | **16.968** | 18.224 | 18.707 | 2858.510 | 7779.460 |
| `hash_join` | **26.986** | 28.193 | 29.486 | 3472.797 | 8329.832 |
| `sieve` | 23.644 | **22.614** | 23.008 | 71.555 | 3236.886 |
| `fib` | **25.462** | 30.014 | 30.292 | 133.576 | 1338.028 |
| `collatz` | 12.422 | **12.343** | 12.574 | 51.434 | 746.116 |
| `matmul` | 34.043 | **33.859** | 34.016 | 79.378 | 3317.203 |
| `json_parse` | **8.525** | 8.662 | 11.944 | 36.485 | 39.325 |
| `nbody` | **25.225** | 39.999 | 25.388 | 102.324 | 3040.439 |
| `chacha20` | **7.383** | 42.144 | 33.706 | n/a | n/a |
| `poly1305` | **11.801** | 31.831 | 21.264 | n/a | n/a |
| `blake2b` | **44.360** | 65.244 | 69.403 | n/a | n/a |
| `sha512` | **47.435** | 50.572 | 49.667 | n/a | n/a |
| `x25519` | **31.663** | 48.763 | 49.607 | n/a | n/a |

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
| _(floor: empty program)_ | _4.638_ | _121.468_ | _**126.106**_ | _66.834_ | _88.426_ | _65.691_ |
| `lcg` | 4.896 | 136.778 | **141.674** | 67.387 | 98.584 | 72.828 |
| `packet_classifier` | 4.989 | 134.741 | **139.730** | 66.811 | 98.297 | 73.637 |
| `ring_write` | 15.542 | 134.621 | **150.163** | 75.866 | 98.139 | 75.172 |
| `histogram_bins` | 15.632 | 136.216 | **151.848** | 77.312 | 116.611 | 82.725 |
| `prefix_scan` | 15.932 | 136.552 | **152.484** | 74.718 | 101.073 | 76.029 |
| `binary_search` | 15.914 | 138.526 | **154.440** | 76.662 | 99.928 | 81.858 |
| `sort_window` | 16.129 | 141.449 | **157.578** | 76.480 | 110.416 | 85.102 |
| `bloom_filter` | 16.578 | 138.463 | **155.041** | 77.047 | 108.552 | 80.066 |
| `hash_join` | 20.428 | 270.774 | **291.202** | 80.768 | 224.145 | 127.378 |
| `sieve` | 16.007 | 138.625 | **154.632** | 76.321 | 110.077 | 86.150 |
| `fib` | 4.975 | 134.222 | **139.197** | 66.769 | 98.844 | 71.751 |
| `collatz` | 5.173 | 137.179 | **142.352** | 66.876 | 97.945 | 76.146 |
| `matmul` | 17.434 | 138.838 | **156.272** | 78.237 | 112.854 | 98.031 |
| `json_parse` | 51.675 | 482.381 | **534.056** | 114.046 | 165.920 | 176.775 |
| `nbody` | 18.475 | 140.491 | **158.966** | 77.370 | 131.310 | 110.398 |
| `chacha20` | 58.059 | 756.063 | **814.122** | 119.441 | 145.922 | 122.162 |
| `poly1305` | 44.997 | 515.290 | **560.287** | 105.604 | 145.349 | 137.258 |
| `blake2b` | 39.525 | 379.855 | **419.380** | 101.567 | 150.763 | 132.967 |
| `sha512` | 39.878 | 479.300 | **519.178** | 101.094 | 145.702 | 118.621 |
| `x25519` | 54.043 | 1296.863 | **1350.906** | 115.879 | 1220.273 | 514.942 |

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
