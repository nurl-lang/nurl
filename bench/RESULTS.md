# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-08T07:55:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `d8561da68d3f93ce07777bfacff5aa35165e80e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37746051259 |
| NURL | `v0.71.0-4-gd8561da6` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
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
| _(floor: empty program)_ | _1.149_ | _1.148_ | _1.326_ | _18.317_ | _11.955_ |
| `lcg` | **29.489** | 29.668 | 29.687 | 1121.174 | 3145.709 |
| `packet_classifier` | **42.435** | 42.533 | 43.565 | 131.657 | 2625.106 |
| `ring_write` | 29.656 | **29.625** | 29.860 | 50.484 | 3722.531 |
| `histogram_bins` | 29.478 | **29.302** | 29.596 | 50.498 | 3491.032 |
| `prefix_scan` | 16.219 | **16.051** | 16.831 | 47.503 | 2559.716 |
| `binary_search` | 14.371 | **14.171** | 15.149 | 68.688 | 3504.020 |
| `sort_window` | 19.812 | **19.560** | 20.238 | 134.476 | 7116.642 |
| `bloom_filter` | **8.851** | 8.941 | 9.140 | 1610.874 | 4545.023 |
| `hash_join` | **16.534** | 17.343 | 18.296 | 1923.463 | 4462.282 |
| `sieve` | 11.930 | 12.079 | **11.574** | 46.188 | 1791.337 |
| `fib` | 19.203 | 18.794 | **18.739** | 75.285 | 650.526 |
| `collatz` | 9.345 | **9.216** | 9.419 | 37.851 | 413.445 |
| `matmul` | **20.477** | 21.415 | 21.264 | 53.817 | 1855.745 |
| `json_parse` | **5.120** | 5.406 | 7.152 | 26.400 | 26.148 |
| `nbody` | **17.014** | 25.022 | 17.287 | 60.556 | 1459.717 |
| `chacha20` | 29.238 | 20.508 | **19.651** | n/a | n/a |
| `poly1305` | **25.822** | 26.005 | 32.067 | n/a | n/a |
| `blake2b` | 117.461 | **45.082** | 48.310 | n/a | n/a |
| `sha512` | 32.899 | **32.755** | 33.016 | n/a | n/a |
| `x25519` | 35.088 | **30.806** | 31.373 | n/a | n/a |

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
| _(floor: empty program)_ | _2.830_ | _80.108_ | _**82.938**_ | _48.102_ | _66.206_ | _50.567_ |
| `lcg` | 2.964 | 86.645 | **89.609** | 48.361 | 71.360 | 56.303 |
| `packet_classifier` | 3.030 | 89.258 | **92.288** | 49.057 | 73.582 | 57.655 |
| `ring_write` | 3.091 | 89.629 | **92.720** | 49.377 | 76.188 | 58.429 |
| `histogram_bins` | 3.294 | 93.731 | **97.025** | 49.365 | 85.543 | 62.522 |
| `prefix_scan` | 3.212 | 91.650 | **94.862** | 49.400 | 77.662 | 60.535 |
| `binary_search` | 3.492 | 91.337 | **94.829** | 50.237 | 78.146 | 63.121 |
| `sort_window` | 3.344 | 86.894 | **90.238** | 47.206 | 77.346 | 62.668 |
| `bloom_filter` | 3.735 | 91.593 | **95.328** | 49.643 | 82.185 | 62.388 |
| `hash_join` | 5.742 | 173.074 | **178.816** | 50.424 | 144.880 | 92.805 |
| `sieve` | 3.347 | 88.971 | **92.318** | 48.857 | 81.180 | 66.551 |
| `fib` | 3.158 | 89.242 | **92.400** | 49.043 | 77.787 | 56.854 |
| `collatz` | 3.081 | 87.609 | **90.690** | 47.592 | 74.735 | 59.096 |
| `matmul` | 3.940 | 89.729 | **93.669** | 49.984 | 103.070 | 71.603 |
| `json_parse` | 29.647 | 308.928 | **338.575** | 76.475 | 115.269 | 131.606 |
| `nbody` | 4.529 | 100.284 | **104.813** | 50.079 | 94.781 | 82.086 |
| `chacha20` | 21.568 | 209.109 | **230.677** | 66.273 | 103.648 | 159.160 |
| `poly1305` | 14.686 | 167.674 | **182.360** | 63.026 | 116.697 | 104.822 |
| `blake2b` | 22.430 | 276.459 | **298.889** | 68.486 | 108.996 | 116.572 |
| `sha512` | 19.921 | 272.954 | **292.875** | 66.944 | 103.049 | 87.034 |
| `x25519` | 23.506 | 246.452 | **269.958** | 70.347 | 746.340 | 331.839 |

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
  five, carry the same formulation written out by hand: poly1305-donna-64
  and the donna-c64 X25519 field with native 128-bit products, scalar
  ChaCha20 (the stdlib runs it on `v128` lanes). Each source names its
  RFC/FIPS test vector; x25519 at x1 reproduces RFC 7748's 1000-iteration
  value.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
