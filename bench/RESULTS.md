# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T16:44:34Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16377684 KiB |
| Commit | `e9765a56ce9a74cd178fbc2dec92f4acfea9f176` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39988463291 |
| NURL | `v0.77.2-8-ge9765a56` |
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
| _(floor: empty program)_ | _1.517_ | _1.480_ | _1.629_ | _25.844_ | _18.399_ |
| `lcg` | **39.053** | 39.117 | 39.354 | 1892.331 | 5064.990 |
| `packet_classifier` | **56.305** | 56.418 | 56.529 | 163.044 | 4470.356 |
| `ring_write` | 42.244 | **42.231** | 42.587 | 66.646 | 6460.467 |
| `histogram_bins` | 40.653 | **40.621** | 40.958 | 67.060 | 6508.780 |
| `prefix_scan` | **21.639** | 21.732 | 22.014 | 67.149 | 4494.019 |
| `binary_search` | 38.395 | **38.338** | 41.009 | 108.717 | 5998.736 |
| `sort_window` | 26.611 | **26.597** | 26.906 | 199.048 | 11522.056 |
| `bloom_filter` | **15.338** | 17.795 | 18.331 | 2833.808 | 7866.385 |
| `hash_join` | **27.097** | 27.942 | 29.438 | 3401.968 | 8454.648 |
| `sieve` | 18.459 | **18.117** | 20.152 | 66.677 | 3528.617 |
| `fib` | 29.882 | **29.855** | 30.153 | 131.990 | 1387.057 |
| `collatz` | 12.352 | **12.341** | 12.597 | 51.963 | 739.602 |
| `matmul` | 33.732 | **33.528** | 33.824 | 78.028 | 3187.255 |
| `json_parse` | **8.157** | 8.605 | 11.714 | 36.560 | 39.845 |
| `nbody` | 25.362 | 39.861 | **25.311** | 100.720 | 3224.030 |
| `chacha20` | **7.576** | 40.498 | 33.593 | n/a | n/a |
| `poly1305` | 23.401 | 31.831 | **21.269** | n/a | n/a |
| `blake2b` | **43.645** | 65.097 | 69.548 | n/a | n/a |
| `sha512` | **46.468** | 50.748 | 49.616 | n/a | n/a |
| `x25519` | **44.237** | 48.729 | 49.655 | n/a | n/a |

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
| _(floor: empty program)_ | _4.770_ | _115.623_ | _**120.393**_ | _64.582_ | _84.967_ | _62.058_ |
| `lcg` | 4.536 | 125.674 | **130.210** | 63.760 | 93.104 | 62.992 |
| `packet_classifier` | 4.596 | 128.063 | **132.659** | 65.005 | 96.164 | 60.354 |
| `ring_write` | 13.638 | 127.456 | **141.094** | 71.645 | 93.549 | 61.161 |
| `histogram_bins` | 14.114 | 130.664 | **144.778** | 74.812 | 114.559 | 68.877 |
| `prefix_scan` | 13.803 | 127.591 | **141.394** | 72.112 | 99.037 | 62.801 |
| `binary_search` | 14.378 | 126.802 | **141.180** | 73.310 | 98.343 | 66.337 |
| `sort_window` | 14.517 | 132.579 | **147.096** | 74.573 | 105.975 | 71.954 |
| `bloom_filter` | 15.021 | 131.892 | **146.913** | 73.635 | 103.867 | 65.478 |
| `hash_join` | 18.579 | 268.301 | **286.880** | 77.904 | 220.521 | 112.359 |
| `sieve` | 14.313 | 127.110 | **141.423** | 72.906 | 104.638 | 70.168 |
| `fib` | 4.650 | 123.388 | **128.038** | 62.784 | 92.925 | 60.209 |
| `collatz` | 4.904 | 130.771 | **135.675** | 64.820 | 96.412 | 61.599 |
| `matmul` | 16.129 | 131.253 | **147.382** | 76.617 | 111.256 | 82.743 |
| `json_parse` | 47.747 | 493.951 | **541.698** | 107.402 | 161.834 | 157.186 |
| `nbody` | 16.652 | 138.645 | **155.297** | 75.252 | 130.069 | 95.388 |
| `chacha20` | 48.937 | 808.161 | **857.098** | 108.308 | 141.374 | 105.962 |
| `poly1305` | 33.104 | 280.175 | **313.279** | 92.294 | 143.557 | 120.972 |
| `blake2b` | 36.977 | 383.521 | **420.498** | 95.224 | 147.642 | 116.375 |
| `sha512` | 36.973 | 478.207 | **515.180** | 95.597 | 138.863 | 100.152 |
| `x25519` | 36.915 | 823.780 | **860.695** | 97.363 | 1216.823 | 495.939 |

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
