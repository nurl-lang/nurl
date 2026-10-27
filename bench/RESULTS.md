# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T14:31:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `29a68f8576869551fd6d4f9dc49d909e33610a06` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40520939115 |
| NURL | `v0.78.0-52-g29a68f85` |
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
| _(floor: empty program)_ | _1.529_ | _1.501_ | _1.694_ | _25.134_ | _19.421_ |
| `lcg` | **39.178** | 39.204 | 39.560 | 1912.171 | 5094.679 |
| `packet_classifier` | 56.418 | **56.388** | 56.704 | 164.490 | 4409.559 |
| `ring_write` | 42.456 | **42.357** | 42.633 | 67.693 | 6638.506 |
| `histogram_bins` | 40.852 | **40.845** | 41.117 | 71.242 | 6077.619 |
| `prefix_scan` | **21.789** | 21.990 | 22.444 | 70.302 | 4465.897 |
| `binary_search` | 38.406 | **38.314** | 41.141 | 107.960 | 6913.877 |
| `sort_window` | **26.671** | 26.685 | 27.061 | 199.313 | 11720.946 |
| `bloom_filter` | **15.342** | 17.881 | 18.370 | 2873.673 | 8240.565 |
| `hash_join` | **27.133** | 28.013 | 29.273 | 3436.606 | 8235.594 |
| `sieve` | 18.908 | **18.226** | 18.564 | 69.351 | 3268.048 |
| `fib` | **29.845** | 29.985 | 30.433 | 132.682 | 1363.761 |
| `collatz` | 12.275 | **12.214** | 12.537 | 51.569 | 744.856 |
| `matmul` | 35.446 | 34.919 | **34.170** | 77.552 | 3180.233 |
| `json_parse` | **8.247** | 8.768 | 11.856 | 39.276 | 39.061 |
| `nbody` | **25.341** | 39.879 | 26.875 | 105.374 | 3154.992 |
| `chacha20` | **7.431** | 40.762 | 33.894 | n/a | n/a |
| `poly1305` | **11.809** | 31.960 | 21.571 | n/a | n/a |
| `blake2b` | **43.899** | 65.279 | 69.594 | n/a | n/a |
| `sha512` | **46.574** | 50.744 | 49.674 | n/a | n/a |
| `x25519` | **44.704** | 48.782 | 49.772 | n/a | n/a |

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
| _(floor: empty program)_ | _4.576_ | _126.157_ | _**130.733**_ | _69.588_ | _86.103_ | _56.798_ |
| `lcg` | 4.880 | 137.676 | **142.556** | 71.538 | 96.825 | 60.545 |
| `packet_classifier` | 4.689 | 134.520 | **139.209** | 67.043 | 98.099 | 62.287 |
| `ring_write` | 15.970 | 141.159 | **157.129** | 78.968 | 100.053 | 63.191 |
| `histogram_bins` | 15.357 | 137.657 | **153.014** | 76.655 | 115.344 | 69.218 |
| `prefix_scan` | 15.845 | 140.296 | **156.141** | 77.674 | 105.464 | 66.590 |
| `binary_search` | 16.094 | 138.981 | **155.075** | 77.911 | 102.007 | 71.197 |
| `sort_window` | 15.932 | 140.043 | **155.975** | 77.084 | 109.726 | 71.748 |
| `bloom_filter` | 16.676 | 141.921 | **158.597** | 78.446 | 108.361 | 68.379 |
| `hash_join` | 20.605 | 290.315 | **310.920** | 83.589 | 232.382 | 115.334 |
| `sieve` | 16.103 | 136.088 | **152.191** | 77.552 | 110.287 | 73.669 |
| `fib` | 5.018 | 137.209 | **142.227** | 68.351 | 100.662 | 62.495 |
| `collatz` | 4.970 | 134.359 | **139.329** | 65.573 | 98.729 | 61.771 |
| `matmul` | 17.399 | 138.231 | **155.630** | 79.080 | 113.292 | 81.852 |
| `json_parse` | 52.489 | 509.191 | **561.680** | 116.219 | 168.847 | 163.125 |
| `nbody` | 18.236 | 145.587 | **163.823** | 79.526 | 133.416 | 97.035 |
| `chacha20` | 59.698 | 795.442 | **855.140** | 122.241 | 151.806 | 114.839 |
| `poly1305` | 44.581 | 528.433 | **573.014** | 107.811 | 151.974 | 129.982 |
| `blake2b` | 42.173 | 401.198 | **443.371** | 106.098 | 155.556 | 118.595 |
| `sha512` | 40.425 | 493.417 | **533.842** | 102.571 | 146.073 | 103.366 |
| `x25519` | 39.345 | 859.050 | **898.395** | 101.120 | 1237.400 | 500.554 |

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
