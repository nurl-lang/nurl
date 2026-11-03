# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-03T09:35:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `12abebe43b46db1695a0ebe21cd648009df8ca99` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41611417438 |
| NURL | `v0.85.0-56-g12abebe4` |
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
| _(floor: empty program)_ | _3.808_ | _3.934_ | _4.312_ | _31.397_ | _18.295_ |
| `lcg` | 41.420 | **41.321** | 41.476 | 1821.902 | 5003.838 |
| `packet_classifier` | 58.692 | **58.671** | 58.922 | 168.036 | 4135.753 |
| `ring_write` | 44.514 | **44.397** | 44.705 | 71.113 | 6362.103 |
| `histogram_bins` | **41.715** | 43.090 | 42.892 | 71.365 | 5608.434 |
| `prefix_scan` | 23.857 | **23.788** | 24.019 | 66.408 | 4225.763 |
| `binary_search` | 42.040 | **40.737** | 43.406 | 110.710 | 6076.336 |
| `sort_window` | 29.343 | **29.313** | 29.407 | 198.801 | 11905.836 |
| `bloom_filter` | **19.184** | 20.195 | 20.744 | 2855.131 | 7153.946 |
| `hash_join` | 29.012 | **28.871** | 31.634 | 3365.838 | 7777.676 |
| `sieve` | 25.006 | 24.795 | **24.705** | 73.390 | 3230.927 |
| `fib` | **27.431** | 32.363 | 32.340 | 134.958 | 1127.344 |
| `collatz` | 14.537 | **14.481** | 14.678 | 56.183 | 685.781 |
| `matmul` | 36.028 | **35.787** | 36.121 | 76.463 | 2961.445 |
| `json_parse` | **9.253** | 13.604 | 18.730 | 41.091 | 37.858 |
| `nbody` | **26.226** | 41.747 | 27.424 | 103.186 | 2960.352 |
| `chacha20` | **9.631** | 43.367 | 35.968 | n/a | n/a |
| `poly1305` | **13.605** | 34.243 | 23.306 | n/a | n/a |
| `blake2b` | **46.062** | 66.874 | 71.244 | n/a | n/a |
| `sha512` | 49.770 | **49.527** | 51.542 | n/a | n/a |
| `x25519` | **34.412** | 51.002 | 51.517 | n/a | n/a |

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
| _(floor: empty program)_ | _7.345_ | _132.648_ | _**139.993**_ | _71.185_ | _90.505_ | _69.094_ |
| `lcg` | 7.706 | 145.923 | **153.629** | 68.729 | 96.460 | 73.662 |
| `packet_classifier` | 7.362 | 139.084 | **146.446** | 68.659 | 93.815 | 74.251 |
| `ring_write` | 15.607 | 135.252 | **150.859** | 74.718 | 95.004 | 74.572 |
| `histogram_bins` | 15.759 | 137.404 | **153.163** | 75.000 | 138.170 | 84.411 |
| `prefix_scan` | 15.704 | 138.341 | **154.045** | 74.993 | 98.443 | 78.678 |
| `binary_search` | 16.572 | 144.205 | **160.777** | 78.818 | 103.913 | 91.514 |
| `sort_window` | 17.118 | 148.113 | **165.231** | 80.414 | 112.632 | 88.641 |
| `bloom_filter` | 17.690 | 149.001 | **166.691** | 80.279 | 108.077 | 83.257 |
| `hash_join` | 20.612 | 274.070 | **294.682** | 80.490 | 227.054 | 131.546 |
| `sieve` | 16.199 | 137.690 | **153.889** | 76.075 | 108.295 | 89.291 |
| `fib` | 7.088 | 132.214 | **139.302** | 64.239 | 91.924 | 73.749 |
| `collatz` | 7.742 | 143.508 | **151.250** | 70.134 | 97.544 | 74.415 |
| `matmul` | 16.609 | 141.040 | **157.649** | 76.342 | 112.460 | 98.414 |
| `json_parse` | 48.398 | 349.991 | **398.389** | 110.002 | 163.516 | 183.600 |
| `nbody` | 18.556 | 144.073 | **162.629** | 78.775 | 131.774 | 114.977 |
| `chacha20` | 69.561 | 695.728 | **765.289** | 131.011 | 146.256 | 123.058 |
| `poly1305` | 57.924 | 426.055 | **483.979** | 119.351 | 151.287 | 135.461 |
| `blake2b` | 37.425 | 341.955 | **379.380** | 95.671 | 148.048 | 137.784 |
| `sha512` | 35.959 | 457.824 | **493.783** | 93.942 | 139.178 | 116.852 |
| `x25519` | 52.395 | 1397.799 | **1450.194** | 109.974 | 1244.918 | 509.987 |

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
