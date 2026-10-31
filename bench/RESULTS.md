# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T06:33:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `884ff4ae81e1471f186614300a533806085c6833` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41176661346 |
| NURL | `v0.81.0-49-g884ff4ae` |
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
| _(floor: empty program)_ | _3.408_ | _3.298_ | _3.478_ | _26.769_ | _14.905_ |
| `lcg` | 41.217 | **40.973** | 41.208 | 1783.660 | 5811.914 |
| `packet_classifier` | 58.593 | **58.459** | 58.701 | 166.078 | 4017.726 |
| `ring_write` | 44.293 | **44.100** | 44.365 | 69.647 | 6185.850 |
| `histogram_bins` | **41.579** | 42.613 | 42.992 | 72.430 | 5703.374 |
| `prefix_scan` | 23.761 | **23.690** | 23.940 | 67.891 | 4105.827 |
| `binary_search` | 41.780 | **40.134** | 42.818 | 109.758 | 5940.910 |
| `sort_window` | 28.608 | **28.596** | 28.761 | 198.541 | 12043.103 |
| `bloom_filter` | **18.761** | 19.837 | 20.240 | 2888.907 | 7209.159 |
| `hash_join` | 28.945 | **28.567** | 31.329 | 3391.838 | 7669.977 |
| `sieve` | 24.777 | **24.552** | 26.481 | 74.960 | 3257.026 |
| `fib` | **27.129** | 31.760 | 31.881 | 136.005 | 1133.385 |
| `collatz` | 14.253 | **14.048** | 14.318 | 54.614 | 684.447 |
| `matmul` | 35.650 | **35.492** | 35.632 | 73.939 | 3194.793 |
| `json_parse` | **10.374** | 13.157 | 18.417 | 39.032 | 36.325 |
| `nbody` | **26.035** | 41.700 | 27.245 | 102.672 | 3033.457 |
| `chacha20` | **9.606** | 43.545 | 35.776 | n/a | n/a |
| `poly1305` | **13.932** | 34.621 | 23.798 | n/a | n/a |
| `blake2b` | **46.044** | 67.057 | 71.356 | n/a | n/a |
| `sha512` | **49.307** | 49.329 | 51.505 | n/a | n/a |
| `x25519` | **33.595** | 51.195 | 51.599 | n/a | n/a |

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
| _(floor: empty program)_ | _6.469_ | _118.029_ | _**124.498**_ | _63.095_ | _77.952_ | _65.272_ |
| `lcg` | 6.632 | 127.313 | **133.945** | 62.896 | 88.793 | 71.241 |
| `packet_classifier` | 6.797 | 128.262 | **135.059** | 63.435 | 90.610 | 73.554 |
| `ring_write` | 17.049 | 133.549 | **150.598** | 74.493 | 92.838 | 74.426 |
| `histogram_bins` | 17.433 | 131.682 | **149.115** | 73.308 | 133.577 | 83.145 |
| `prefix_scan` | 17.245 | 131.392 | **148.637** | 73.394 | 97.278 | 76.234 |
| `binary_search` | 17.419 | 130.341 | **147.760** | 73.644 | 92.920 | 77.900 |
| `sort_window` | 17.639 | 133.619 | **151.258** | 74.005 | 102.269 | 84.044 |
| `bloom_filter` | 18.540 | 138.088 | **156.628** | 76.664 | 104.121 | 80.271 |
| `hash_join` | 21.459 | 267.800 | **289.259** | 77.770 | 216.607 | 124.356 |
| `sieve` | 17.401 | 130.558 | **147.959** | 73.616 | 103.519 | 95.277 |
| `fib` | 6.864 | 128.757 | **135.621** | 63.941 | 91.116 | 72.472 |
| `collatz` | 7.049 | 130.381 | **137.430** | 62.804 | 91.158 | 72.715 |
| `matmul` | 18.068 | 133.734 | **151.802** | 74.924 | 106.718 | 94.527 |
| `json_parse` | 51.622 | 451.181 | **502.803** | 109.654 | 158.499 | 174.961 |
| `nbody` | 19.568 | 137.083 | **156.651** | 75.868 | 127.235 | 110.002 |
| `chacha20` | 58.190 | 779.819 | **838.009** | 116.584 | 143.398 | 122.933 |
| `poly1305` | 45.613 | 510.646 | **556.259** | 108.369 | 148.763 | 142.567 |
| `blake2b` | 41.126 | 343.050 | **384.176** | 101.157 | 147.856 | 132.655 |
| `sha512` | 40.882 | 455.169 | **496.051** | 99.398 | 138.292 | 117.570 |
| `x25519` | 54.954 | 1543.788 | **1598.742** | 112.429 | 1240.974 | 514.094 |

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
