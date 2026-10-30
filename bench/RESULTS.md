# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T07:12:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `3127bf0ee9952beb692deab8ea1dc662306b3187` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41018024502 |
| NURL | `v0.80.0-111-g3127bf0e` |
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
| _(floor: empty program)_ | _1.683_ | _1.629_ | _1.886_ | _26.645_ | _19.402_ |
| `lcg` | 44.385 | **44.276** | 44.531 | 1845.971 | 5425.604 |
| `packet_classifier` | 63.770 | **63.710** | 63.859 | 161.163 | 4514.303 |
| `ring_write` | 47.926 | **47.856** | 48.089 | 77.218 | 6769.966 |
| `histogram_bins` | **44.763** | 44.812 | 44.968 | 77.685 | 6119.353 |
| `prefix_scan` | **24.674** | 24.704 | 24.958 | 74.517 | 4930.073 |
| `binary_search` | 41.801 | **35.975** | 43.652 | 113.003 | 6510.243 |
| `sort_window` | 30.252 | **30.245** | 30.471 | 168.990 | 11232.940 |
| `bloom_filter` | 19.286 | **19.060** | 21.019 | 2807.188 | 7857.614 |
| `hash_join` | **27.958** | 28.750 | 30.316 | 3428.697 | 8229.206 |
| `sieve` | 25.781 | **24.445** | 24.602 | 77.039 | 3693.608 |
| `fib` | **28.166** | 33.516 | 33.578 | 144.581 | 1290.710 |
| `collatz` | 13.903 | **13.839** | 14.211 | 56.369 | 753.532 |
| `matmul` | **44.917** | 45.359 | 46.490 | 85.947 | 3746.747 |
| `json_parse` | **8.345** | 9.114 | 12.502 | 41.619 | 41.987 |
| `nbody` | 27.069 | 45.196 | **27.065** | 97.536 | 3301.025 |
| `chacha20` | **9.025** | 46.348 | 35.850 | n/a | n/a |
| `poly1305` | **12.756** | 40.394 | 24.200 | n/a | n/a |
| `blake2b` | **49.455** | 71.975 | 78.194 | n/a | n/a |
| `sha512` | **50.109** | 52.079 | 54.826 | n/a | n/a |
| `x25519` | **35.859** | 54.436 | 56.332 | n/a | n/a |

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
| _(floor: empty program)_ | _5.247_ | _131.399_ | _**136.646**_ | _73.069_ | _96.808_ | _70.617_ |
| `lcg` | 5.525 | 144.303 | **149.828** | 73.985 | 105.347 | 79.750 |
| `packet_classifier` | 5.671 | 146.526 | **152.197** | 75.255 | 108.237 | 80.630 |
| `ring_write` | 17.163 | 147.494 | **164.657** | 84.363 | 108.459 | 81.946 |
| `histogram_bins` | 16.964 | 145.884 | **162.848** | 84.124 | 123.946 | 89.406 |
| `prefix_scan` | 17.460 | 148.332 | **165.792** | 84.587 | 114.621 | 85.947 |
| `binary_search` | 17.322 | 146.027 | **163.349** | 84.337 | 110.171 | 87.680 |
| `sort_window` | 17.403 | 149.209 | **166.612** | 84.765 | 119.478 | 92.624 |
| `bloom_filter` | 17.911 | 152.103 | **170.014** | 85.389 | 120.857 | 88.623 |
| `hash_join` | 21.379 | 270.272 | **291.651** | 88.828 | 225.541 | 136.460 |
| `sieve` | 17.315 | 146.477 | **163.792** | 84.860 | 118.842 | 95.155 |
| `fib` | 5.756 | 145.708 | **151.464** | 74.281 | 107.488 | 82.336 |
| `collatz` | 5.823 | 147.442 | **153.265** | 75.041 | 107.405 | 81.961 |
| `matmul` | 18.530 | 148.231 | **166.761** | 85.814 | 121.914 | 104.458 |
| `json_parse` | 53.291 | 475.941 | **529.232** | 122.877 | 174.472 | 193.100 |
| `nbody` | 20.111 | 152.443 | **172.554** | 87.451 | 141.607 | 122.495 |
| `chacha20` | 60.329 | 765.326 | **825.655** | 129.415 | 154.436 | 134.200 |
| `poly1305` | 45.931 | 524.515 | **570.446** | 115.029 | 157.062 | 148.603 |
| `blake2b` | 42.395 | 384.135 | **426.530** | 111.322 | 161.954 | 145.301 |
| `sha512` | 41.645 | 475.665 | **517.310** | 110.035 | 154.533 | 129.379 |
| `x25519` | 56.580 | 1271.722 | **1328.302** | 125.374 | 1221.089 | 533.693 |

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
