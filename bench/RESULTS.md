# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T09:22:39Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `53a2af839090f50f313c0091dd9215e46d3403c0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41188001746 |
| NURL | `v0.82.0-18-g53a2af83` |
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
| _(floor: empty program)_ | _3.511_ | _3.608_ | _3.767_ | _27.911_ | _15.487_ |
| `lcg` | **41.681** | 41.745 | 42.060 | 1806.335 | 4933.442 |
| `packet_classifier` | 58.812 | **58.652** | 59.083 | 167.675 | 4115.646 |
| `ring_write` | **44.769** | 44.781 | 44.981 | 72.627 | 6429.462 |
| `histogram_bins` | **42.099** | 43.502 | 43.701 | 71.989 | 5724.664 |
| `prefix_scan` | **24.020** | 24.046 | 24.417 | 69.231 | 4137.873 |
| `binary_search` | 41.958 | **40.907** | 43.351 | 110.948 | 6006.021 |
| `sort_window` | 29.280 | **29.014** | 29.165 | 198.597 | 11787.886 |
| `bloom_filter` | **18.739** | 19.975 | 20.469 | 2880.751 | 7117.585 |
| `hash_join` | **28.937** | 29.000 | 31.869 | 3371.838 | 8009.779 |
| `sieve` | **26.603** | 26.685 | 26.939 | 75.747 | 3111.685 |
| `fib` | **27.881** | 32.437 | 32.639 | 136.013 | 1111.314 |
| `collatz` | **14.615** | 14.833 | 15.285 | 56.013 | 695.621 |
| `matmul` | 36.202 | **36.107** | 36.247 | 76.036 | 3039.132 |
| `json_parse` | **10.689** | 13.607 | 19.663 | 42.467 | 38.724 |
| `nbody` | **26.646** | 42.941 | 27.965 | 106.917 | 2964.081 |
| `chacha20` | **9.836** | 43.906 | 36.342 | n/a | n/a |
| `poly1305` | **13.602** | 34.091 | 23.454 | n/a | n/a |
| `blake2b` | **46.567** | 67.160 | 71.615 | n/a | n/a |
| `sha512` | **49.925** | 49.959 | 51.976 | n/a | n/a |
| `x25519` | **34.624** | 51.422 | 52.099 | n/a | n/a |

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
| _(floor: empty program)_ | _6.784_ | _123.384_ | _**130.168**_ | _66.648_ | _82.102_ | _65.424_ |
| `lcg` | 6.846 | 133.501 | **140.347** | 66.946 | 92.952 | 73.034 |
| `packet_classifier` | 7.165 | 133.347 | **140.512** | 66.696 | 97.623 | 75.559 |
| `ring_write` | 17.211 | 136.793 | **154.004** | 76.634 | 96.492 | 75.534 |
| `histogram_bins` | 17.123 | 138.763 | **155.886** | 76.445 | 140.463 | 85.454 |
| `prefix_scan` | 17.400 | 136.729 | **154.129** | 77.656 | 101.620 | 79.212 |
| `binary_search` | 17.234 | 136.394 | **153.628** | 76.367 | 96.834 | 80.258 |
| `sort_window` | 17.410 | 136.870 | **154.280** | 76.053 | 106.866 | 84.221 |
| `bloom_filter` | 17.888 | 139.498 | **157.386** | 76.892 | 106.441 | 82.362 |
| `hash_join` | 21.272 | 274.756 | **296.028** | 81.658 | 220.996 | 128.783 |
| `sieve` | 17.574 | 139.499 | **157.073** | 78.514 | 110.364 | 88.418 |
| `fib` | 7.211 | 135.895 | **143.106** | 68.338 | 94.670 | 75.409 |
| `collatz` | 7.235 | 137.853 | **145.088** | 66.700 | 98.333 | 75.676 |
| `matmul` | 18.144 | 140.870 | **159.014** | 78.648 | 112.462 | 98.738 |
| `json_parse` | 54.203 | 470.926 | **525.129** | 116.256 | 168.873 | 182.496 |
| `nbody` | 19.575 | 144.517 | **164.092** | 79.709 | 136.573 | 116.062 |
| `chacha20` | 60.977 | 784.296 | **845.273** | 122.979 | 149.516 | 127.096 |
| `poly1305` | 47.637 | 519.711 | **567.348** | 108.921 | 153.332 | 139.038 |
| `blake2b` | 40.161 | 342.290 | **382.451** | 100.836 | 150.222 | 135.377 |
| `sha512` | 39.935 | 469.580 | **509.515** | 101.595 | 145.542 | 121.981 |
| `x25519` | 55.776 | 1565.599 | **1621.375** | 117.098 | 1256.347 | 520.945 |

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
