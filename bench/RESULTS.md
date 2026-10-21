# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-21T19:08:51Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367520 KiB |
| Commit | `403dfeecb1a10c68e8b0105c65253e106dcc6d8b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39658291954 |
| NURL | `v0.76.0-19-g403dfeec` |
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
| _(floor: empty program)_ | _1.309_ | _1.277_ | _1.478_ | _20.806_ | _14.370_ |
| `lcg` | 34.328 | **34.296** | 34.436 | 1413.335 | 4415.111 |
| `packet_classifier` | 49.405 | **49.355** | 49.550 | 125.276 | 3551.548 |
| `ring_write` | 37.075 | **37.019** | 37.197 | 59.375 | 5042.740 |
| `histogram_bins` | 34.723 | **34.703** | 34.929 | 60.027 | 4973.527 |
| `prefix_scan` | 19.037 | **18.999** | 19.158 | 57.492 | 3853.463 |
| `binary_search` | **26.001** | 27.721 | 33.584 | 89.202 | 5188.273 |
| `sort_window` | 23.341 | **23.334** | 23.551 | 130.524 | 10867.207 |
| `bloom_filter` | **13.469** | 14.585 | 16.066 | 2130.397 | 5994.505 |
| `hash_join` | **21.628** | 22.293 | 23.457 | 2676.510 | 6329.286 |
| `sieve` | 19.568 | **18.550** | 18.738 | 60.461 | 2656.441 |
| `fib` | **25.788** | 25.874 | 25.959 | 112.587 | 1000.417 |
| `collatz` | 10.714 | **10.682** | 10.925 | 42.084 | 583.667 |
| `matmul` | **35.424** | 36.085 | 36.056 | 67.170 | 2581.631 |
| `json_parse` | **6.341** | 6.960 | 9.538 | 30.859 | 30.715 |
| `nbody` | 21.023 | 34.917 | **20.909** | 75.723 | 2759.504 |
| `chacha20` | **7.147** | 35.902 | 27.754 | n/a | n/a |
| `poly1305` | 20.560 | 31.295 | **18.587** | n/a | n/a |
| `blake2b` | **37.870** | 55.745 | 60.763 | n/a | n/a |
| `sha512` | **38.722** | 40.406 | 42.442 | n/a | n/a |
| `x25519` | **38.370** | 42.150 | 43.574 | n/a | n/a |

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
| _(floor: empty program)_ | _3.942_ | _94.934_ | _**98.876**_ | _58.463_ | _76.976_ | _55.335_ |
| `lcg` | 4.054 | 103.116 | **107.170** | 56.823 | 83.318 | 62.109 |
| `packet_classifier` | 4.207 | 103.153 | **107.360** | 57.206 | 87.167 | 65.047 |
| `ring_write` | 11.333 | 105.592 | **116.925** | 64.822 | 86.754 | 65.580 |
| `histogram_bins` | 11.348 | 110.923 | **122.271** | 64.448 | 101.032 | 71.583 |
| `prefix_scan` | 11.374 | 105.635 | **117.009** | 64.133 | 88.886 | 67.788 |
| `binary_search` | 11.377 | 105.725 | **117.102** | 63.812 | 85.621 | 67.134 |
| `sort_window` | 11.589 | 109.014 | **120.603** | 64.868 | 94.949 | 71.936 |
| `bloom_filter` | 12.002 | 107.295 | **119.297** | 64.197 | 90.716 | 68.245 |
| `hash_join` | 14.559 | 210.721 | **225.280** | 67.653 | 174.319 | 104.578 |
| `sieve` | 11.495 | 103.664 | **115.159** | 63.558 | 91.165 | 73.545 |
| `fib` | 4.192 | 104.415 | **108.607** | 57.546 | 84.441 | 64.157 |
| `collatz` | 4.275 | 105.061 | **109.336** | 57.679 | 84.596 | 62.957 |
| `matmul` | 12.589 | 105.953 | **118.542** | 65.610 | 94.936 | 80.858 |
| `json_parse` | 36.310 | 372.716 | **409.026** | 89.630 | 135.986 | 149.763 |
| `nbody` | 13.335 | 118.790 | **132.125** | 65.790 | 110.295 | 92.675 |
| `chacha20` | 36.931 | 631.758 | **668.689** | 91.108 | 121.154 | 102.766 |
| `poly1305` | 25.483 | 218.527 | **244.010** | 79.526 | 123.911 | 115.949 |
| `blake2b` | 28.858 | 306.099 | **334.957** | 81.696 | 126.672 | 112.584 |
| `sha512` | 28.250 | 372.475 | **400.725** | 81.820 | 121.269 | 101.312 |
| `x25519` | 28.692 | 633.950 | **662.642** | 83.924 | 941.017 | 407.693 |

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
