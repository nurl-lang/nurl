# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T01:38:43Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1014-aws x86_64` |
| CPU | Intel(R) Xeon(R) 6975P-C (4 logical cores) |
| Memory | 16077560 KiB |
| Commit | `14fb41c217d9d3231e3d493cf63ef71061885626` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41155894439 |
| NURL | `v0.81.0-32-g14fb41c2` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.0 |
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
| _(floor: empty program)_ | _2.454_ | _2.322_ | _2.418_ | _22.258_ | _10.428_ |
| `lcg` | 33.869 | **33.829** | 33.882 | 1107.051 | 3282.168 |
| `packet_classifier` | 58.725 | **58.374** | 58.464 | 139.832 | 2633.618 |
| `ring_write` | **37.294** | 37.774 | 37.393 | 57.476 | 4035.326 |
| `histogram_bins` | **35.191** | 35.199 | 35.398 | 58.879 | 3690.298 |
| `prefix_scan` | 19.665 | **19.599** | 19.615 | 55.174 | 2649.213 |
| `binary_search` | 30.890 | **24.924** | 32.474 | 90.890 | 4357.592 |
| `sort_window` | 33.748 | **33.630** | 34.390 | 144.119 | 7404.804 |
| `bloom_filter` | 13.027 | **12.820** | 12.847 | 1946.568 | 4894.900 |
| `hash_join` | 20.481 | **20.236** | 21.869 | 2412.653 | 5305.314 |
| `sieve` | 37.886 | **36.617** | 36.759 | 73.994 | 2056.673 |
| `fib` | **20.037** | 23.109 | 23.358 | 93.616 | 663.072 |
| `collatz` | **13.336** | 13.488 | 14.501 | 49.090 | 444.393 |
| `matmul` | 17.225 | **16.900** | 17.011 | 54.483 | 1931.697 |
| `json_parse` | **6.575** | 8.157 | 10.829 | 26.042 | 24.053 |
| `nbody` | **18.336** | 25.657 | 18.892 | 63.257 | 1748.726 |
| `chacha20` | **7.774** | 30.849 | 26.965 | n/a | n/a |
| `poly1305` | **11.599** | 28.928 | 21.209 | n/a | n/a |
| `blake2b` | **35.564** | 39.629 | 43.832 | n/a | n/a |
| `sha512` | **35.005** | 35.992 | 41.944 | n/a | n/a |
| `x25519` | **23.979** | 34.623 | 33.913 | n/a | n/a |

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
| _(floor: empty program)_ | _4.596_ | _84.585_ | _**89.181**_ | _45.956_ | _51.525_ | _47.366_ |
| `lcg` | 4.656 | 86.830 | **91.486** | 43.478 | 56.749 | 50.616 |
| `packet_classifier` | 4.969 | 94.935 | **99.904** | 48.499 | 64.711 | 53.452 |
| `ring_write` | 12.983 | 101.375 | **114.358** | 57.904 | 67.165 | 56.274 |
| `histogram_bins` | 12.972 | 98.653 | **111.625** | 55.969 | 97.833 | 59.904 |
| `prefix_scan` | 12.835 | 94.719 | **107.554** | 54.290 | 65.836 | 55.363 |
| `binary_search` | 12.584 | 88.987 | **101.571** | 50.880 | 58.003 | 56.353 |
| `sort_window` | 12.665 | 92.177 | **104.842** | 52.258 | 67.601 | 60.665 |
| `bloom_filter` | 13.205 | 95.359 | **108.564** | 54.653 | 65.184 | 54.658 |
| `hash_join` | 15.745 | 172.617 | **188.362** | 56.644 | 136.450 | 91.388 |
| `sieve` | 12.445 | 86.823 | **99.268** | 50.345 | 64.603 | 60.868 |
| `fib` | 4.619 | 84.872 | **89.491** | 42.013 | 53.938 | 48.145 |
| `collatz` | 4.658 | 86.312 | **90.970** | 41.339 | 53.891 | 49.838 |
| `matmul` | 13.309 | 87.175 | **100.484** | 50.697 | 64.877 | 66.657 |
| `json_parse` | 37.239 | 300.273 | **337.512** | 77.999 | 98.151 | 131.574 |
| `nbody` | 13.870 | 89.254 | **103.124** | 49.660 | 76.127 | 79.659 |
| `chacha20` | 41.219 | 544.786 | **586.005** | 86.125 | 91.070 | 87.146 |
| `poly1305` | 31.349 | 344.093 | **375.442** | 72.750 | 91.587 | 98.654 |
| `blake2b` | 28.883 | 233.754 | **262.637** | 71.406 | 94.387 | 96.780 |
| `sha512` | 29.260 | 309.276 | **338.536** | 73.413 | 90.563 | 85.760 |
| `x25519` | 38.541 | 1093.081 | **1131.622** | 83.441 | 884.258 | 386.237 |

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
