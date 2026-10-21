# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-21T11:53:52Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `e8bc8d72c43b70c885d9f0a5bea1994649f810bd` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39594628430 |
| NURL | `v0.76.0-8-ge8bc8d72` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.3 |
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
| _(floor: empty program)_ | _1.550_ | _1.559_ | _1.746_ | _22.843_ | _17.401_ |
| `lcg` | 39.138 | **39.094** | 39.320 | 1903.211 | 4992.913 |
| `packet_classifier` | 56.352 | **56.341** | 56.377 | 162.833 | 4357.643 |
| `ring_write` | 42.365 | **42.268** | 42.583 | 66.676 | 6419.831 |
| `histogram_bins` | **39.608** | 40.892 | 41.003 | 67.201 | 6431.870 |
| `prefix_scan` | **21.743** | 21.802 | 22.012 | 64.889 | 4558.729 |
| `binary_search` | **36.333** | 38.359 | 41.191 | 107.359 | 6645.737 |
| `sort_window` | 26.716 | **26.626** | 26.872 | 199.602 | 13276.864 |
| `bloom_filter` | **15.640** | 17.959 | 18.416 | 2841.977 | 7537.927 |
| `hash_join` | **27.540** | 28.106 | 29.262 | 3433.514 | 8402.880 |
| `sieve` | 22.422 | **22.008** | 22.048 | 69.790 | 3414.908 |
| `fib` | 29.953 | **29.949** | 30.020 | 132.442 | 1356.836 |
| `collatz` | 12.367 | **12.289** | 12.564 | 49.835 | 740.681 |
| `matmul` | 33.739 | **33.545** | 33.752 | 76.785 | 3117.658 |
| `json_parse` | **8.397** | 8.926 | 12.039 | 37.042 | 39.897 |
| `nbody` | 25.486 | 39.885 | **25.417** | 103.523 | 3132.301 |
| `chacha20` | **7.797** | 40.427 | 33.735 | n/a | n/a |
| `poly1305` | 23.650 | 32.013 | **21.345** | n/a | n/a |
| `blake2b` | **43.624** | 65.041 | 69.003 | n/a | n/a |
| `sha512` | **47.346** | 50.708 | 49.471 | n/a | n/a |
| `x25519` | **44.554** | 48.771 | 49.470 | n/a | n/a |

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
| _(floor: empty program)_ | _4.403_ | _107.565_ | _**111.968**_ | _63.389_ | _81.030_ | _62.948_ |
| `lcg` | 4.521 | 117.645 | **122.166** | 62.905 | 92.952 | 69.943 |
| `packet_classifier` | 4.598 | 116.449 | **121.047** | 61.975 | 92.535 | 72.122 |
| `ring_write` | 13.446 | 119.682 | **133.128** | 71.526 | 95.349 | 73.087 |
| `histogram_bins` | 13.745 | 127.059 | **140.804** | 72.847 | 111.583 | 81.102 |
| `prefix_scan` | 13.695 | 120.447 | **134.142** | 71.403 | 99.894 | 76.520 |
| `binary_search` | 13.767 | 120.771 | **134.538** | 71.171 | 95.602 | 77.753 |
| `sort_window` | 13.972 | 123.363 | **137.335** | 72.223 | 105.666 | 84.394 |
| `bloom_filter` | 14.366 | 124.193 | **138.559** | 72.355 | 104.906 | 79.746 |
| `hash_join` | 17.962 | 269.582 | **287.544** | 78.544 | 221.946 | 126.594 |
| `sieve` | 13.752 | 119.880 | **133.632** | 71.761 | 104.857 | 84.274 |
| `fib` | 4.809 | 117.581 | **122.390** | 63.502 | 93.793 | 73.772 |
| `collatz` | 4.797 | 120.543 | **125.340** | 63.176 | 93.742 | 73.530 |
| `matmul` | 15.389 | 123.233 | **138.622** | 73.831 | 109.441 | 96.958 |
| `json_parse` | 47.001 | 496.476 | **543.477** | 108.483 | 166.185 | 176.739 |
| `nbody` | 16.511 | 140.718 | **157.229** | 76.023 | 133.317 | 114.250 |
| `chacha20` | 46.903 | 790.235 | **837.138** | 107.453 | 144.214 | 124.667 |
| `poly1305` | 31.434 | 274.556 | **305.990** | 90.104 | 143.880 | 140.401 |
| `blake2b` | 36.416 | 385.344 | **421.760** | 96.887 | 149.123 | 132.161 |
| `sha512` | 35.861 | 480.435 | **516.296** | 95.980 | 142.095 | 118.582 |
| `x25519` | 40.260 | 728.136 | **768.396** | 100.335 | 1226.754 | 514.559 |

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
