# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T17:07:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `60a5a569eb5fcfc5bfcce391b7cf02886e2bbeb2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41095105532 |
| NURL | `v0.81.0-4-g60a5a569` |
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
| _(floor: empty program)_ | _3.556_ | _3.470_ | _3.646_ | _27.151_ | _15.837_ |
| `lcg` | 41.699 | **41.607** | 41.864 | 1789.629 | 5096.653 |
| `packet_classifier` | 58.631 | **58.399** | 58.643 | 165.581 | 3971.289 |
| `ring_write` | 44.535 | **44.499** | 44.751 | 70.247 | 6270.853 |
| `histogram_bins` | **42.015** | 42.852 | 43.260 | 72.219 | 5920.922 |
| `prefix_scan` | 23.727 | **23.629** | 23.917 | 67.109 | 4216.577 |
| `binary_search` | 42.384 | **40.910** | 43.671 | 112.574 | 6064.929 |
| `sort_window` | 28.858 | **28.813** | 28.966 | 200.638 | 12036.858 |
| `bloom_filter` | **19.084** | 20.433 | 20.867 | 2920.237 | 7085.601 |
| `hash_join` | 28.951 | **28.938** | 31.457 | 3368.515 | 7648.459 |
| `sieve` | 25.093 | **24.995** | 27.051 | 77.660 | 3044.342 |
| `fib` | **28.078** | 32.774 | 32.939 | 137.820 | 1119.802 |
| `collatz` | 14.854 | **14.658** | 15.125 | 55.894 | 690.983 |
| `matmul` | 36.269 | **36.129** | 36.755 | 77.463 | 3136.853 |
| `json_parse` | **11.185** | 14.039 | 19.528 | 43.396 | 38.977 |
| `nbody` | **26.819** | 42.589 | 28.129 | 106.869 | 2992.889 |
| `chacha20` | **9.738** | 44.291 | 36.551 | n/a | n/a |
| `poly1305` | **14.505** | 34.814 | 23.980 | n/a | n/a |
| `blake2b` | **46.391** | 67.289 | 71.804 | n/a | n/a |
| `sha512` | **49.941** | 50.250 | 52.138 | n/a | n/a |
| `x25519` | **34.444** | 51.709 | 52.006 | n/a | n/a |

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
| _(floor: empty program)_ | _6.753_ | _114.435_ | _**121.188**_ | _67.281_ | _80.555_ | _65.853_ |
| `lcg` | 7.268 | 128.042 | **135.310** | 65.946 | 94.257 | 74.289 |
| `packet_classifier` | 6.882 | 124.522 | **131.404** | 64.677 | 91.782 | 74.023 |
| `ring_write` | 17.296 | 130.661 | **147.957** | 75.600 | 94.491 | 76.644 |
| `histogram_bins` | 17.860 | 133.810 | **151.670** | 77.071 | 139.272 | 82.870 |
| `prefix_scan` | 18.163 | 133.323 | **151.486** | 77.762 | 104.142 | 79.149 |
| `binary_search` | 18.208 | 132.535 | **150.743** | 77.755 | 96.522 | 79.219 |
| `sort_window` | 18.025 | 133.194 | **151.219** | 78.257 | 108.638 | 85.837 |
| `bloom_filter` | 18.435 | 134.914 | **153.349** | 76.899 | 106.978 | 81.766 |
| `hash_join` | 21.894 | 269.695 | **291.589** | 80.065 | 221.177 | 128.997 |
| `sieve` | 17.574 | 126.834 | **144.408** | 73.855 | 104.760 | 87.433 |
| `fib` | 7.761 | 134.169 | **141.930** | 69.559 | 97.266 | 107.700 |
| `collatz` | 7.620 | 138.722 | **146.342** | 70.739 | 101.343 | 76.330 |
| `matmul` | 19.722 | 134.740 | **154.462** | 79.711 | 116.074 | 100.789 |
| `json_parse` | 54.072 | 474.167 | **528.239** | 117.196 | 165.421 | 180.068 |
| `nbody` | 21.307 | 140.832 | **162.139** | 81.720 | 136.823 | 115.986 |
| `chacha20` | 61.490 | 809.987 | **871.477** | 124.879 | 151.021 | 130.908 |
| `poly1305` | 48.164 | 528.096 | **576.260** | 111.278 | 156.426 | 146.210 |
| `blake2b` | 43.775 | 346.605 | **390.380** | 106.597 | 154.774 | 138.496 |
| `sha512` | 43.153 | 471.469 | **514.622** | 105.101 | 143.433 | 119.559 |
| `x25519` | 58.391 | 1577.182 | **1635.573** | 121.565 | 1281.367 | 514.719 |

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
