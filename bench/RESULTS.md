# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T10:21:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c72b590e6e43cdd52812aec372ed763025f49a51` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40487035079 |
| NURL | `v0.78.0-45-gc72b590e` |
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
| _(floor: empty program)_ | _1.504_ | _1.537_ | _1.719_ | _24.431_ | _18.505_ |
| `lcg` | 39.372 | **39.340** | 39.425 | 1907.371 | 5025.927 |
| `packet_classifier` | **56.478** | 56.651 | 56.640 | 165.132 | 4433.403 |
| `ring_write` | 42.448 | **42.408** | 42.603 | 68.979 | 6487.971 |
| `histogram_bins` | 40.977 | **40.949** | 41.037 | 68.507 | 6151.836 |
| `prefix_scan` | **21.802** | 21.831 | 22.149 | 67.423 | 4445.231 |
| `binary_search` | 38.227 | **38.223** | 41.107 | 107.500 | 6025.051 |
| `sort_window` | **26.666** | 26.702 | 26.842 | 197.859 | 12170.454 |
| `bloom_filter` | **15.371** | 17.887 | 18.349 | 2843.617 | 7886.429 |
| `hash_join` | **27.042** | 28.067 | 29.175 | 3401.066 | 8415.214 |
| `sieve` | 20.821 | **20.428** | 20.650 | 68.761 | 3268.224 |
| `fib` | 30.076 | **29.915** | 30.136 | 136.428 | 1363.155 |
| `collatz` | 12.293 | **12.221** | 12.421 | 51.088 | 731.768 |
| `matmul` | **33.583** | 33.759 | 33.807 | 78.893 | 3134.543 |
| `json_parse` | **8.143** | 8.655 | 11.846 | 36.718 | 39.428 |
| `nbody` | 25.301 | 39.737 | **25.253** | 102.355 | 3138.163 |
| `chacha20` | **7.260** | 40.347 | 33.710 | n/a | n/a |
| `poly1305` | **11.563** | 31.832 | 21.158 | n/a | n/a |
| `blake2b` | **43.599** | 64.991 | 68.976 | n/a | n/a |
| `sha512` | **46.506** | 50.613 | 49.618 | n/a | n/a |
| `x25519` | **44.316** | 48.477 | 49.354 | n/a | n/a |

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
| _(floor: empty program)_ | _4.414_ | _121.630_ | _**126.044**_ | _64.875_ | _85.299_ | _56.017_ |
| `lcg` | 4.680 | 133.685 | **138.365** | 65.480 | 94.962 | 61.354 |
| `packet_classifier` | 4.998 | 136.850 | **141.848** | 66.937 | 96.547 | 62.853 |
| `ring_write` | 15.830 | 136.879 | **152.709** | 77.997 | 98.705 | 63.151 |
| `histogram_bins` | 15.716 | 135.548 | **151.264** | 76.556 | 111.336 | 68.555 |
| `prefix_scan` | 15.320 | 135.259 | **150.579** | 75.084 | 102.673 | 65.710 |
| `binary_search` | 15.478 | 131.387 | **146.865** | 74.905 | 98.390 | 65.797 |
| `sort_window` | 15.704 | 134.408 | **150.112** | 74.050 | 104.271 | 70.627 |
| `bloom_filter` | 16.295 | 134.980 | **151.275** | 75.646 | 104.517 | 66.350 |
| `hash_join` | 19.837 | 268.991 | **288.828** | 77.658 | 221.105 | 109.934 |
| `sieve` | 15.531 | 132.199 | **147.730** | 74.206 | 104.690 | 69.875 |
| `fib` | 4.679 | 129.170 | **133.849** | 65.276 | 90.902 | 59.406 |
| `collatz` | 4.792 | 130.270 | **135.062** | 64.170 | 93.235 | 59.450 |
| `matmul` | 16.828 | 131.710 | **148.538** | 75.559 | 108.242 | 79.705 |
| `json_parse` | 49.977 | 497.045 | **547.022** | 109.286 | 161.785 | 157.017 |
| `nbody` | 18.043 | 139.517 | **157.560** | 76.810 | 129.158 | 95.715 |
| `chacha20` | 57.988 | 828.969 | **886.957** | 117.173 | 142.766 | 105.574 |
| `poly1305` | 43.667 | 515.384 | **559.051** | 100.816 | 143.399 | 120.404 |
| `blake2b` | 38.677 | 386.049 | **424.726** | 97.386 | 149.018 | 116.712 |
| `sha512` | 39.129 | 483.270 | **522.399** | 97.703 | 140.370 | 102.213 |
| `x25519` | 39.469 | 836.421 | **875.890** | 98.248 | 1233.795 | 501.205 |

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
