# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-09T10:24:04Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3a3adc975312fd665ed3b8e0032b32424be5181c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/37916790628 |
| NURL | `v0.71.0-11-g3a3adc97` |
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
| _(floor: empty program)_ | _1.477_ | _1.413_ | _1.641_ | _25.124_ | _17.760_ |
| `lcg` | **39.208** | 39.341 | 39.478 | 1926.140 | 5184.143 |
| `packet_classifier` | 56.464 | **56.449** | 56.487 | 164.053 | 4307.136 |
| `ring_write` | 42.422 | **42.338** | 42.716 | 69.608 | 6501.814 |
| `histogram_bins` | **39.944** | 41.086 | 41.025 | 68.892 | 6223.520 |
| `prefix_scan` | **21.955** | 22.014 | 21.987 | 66.405 | 4605.263 |
| `binary_search` | 39.644 | **38.400** | 41.806 | 106.824 | 7563.084 |
| `sort_window` | 26.949 | **26.737** | 26.947 | 199.282 | 11440.765 |
| `bloom_filter` | **15.633** | 18.135 | 18.463 | 2857.715 | 7516.465 |
| `hash_join` | **27.153** | 28.196 | 29.398 | 3422.144 | 8274.795 |
| `sieve` | 20.628 | 20.539 | **20.234** | 72.291 | 3234.894 |
| `fib` | **25.389** | 30.097 | 30.610 | 133.634 | 1347.165 |
| `collatz` | 12.500 | **12.276** | 12.579 | 52.658 | 757.420 |
| `matmul` | 34.135 | **33.814** | 34.249 | 77.504 | 3417.856 |
| `json_parse` | 8.725 | **8.713** | 12.058 | 39.793 | 42.005 |
| `nbody` | 25.942 | 40.301 | **25.835** | 104.483 | 3101.537 |
| `chacha20` | **21.531** | 40.658 | 33.954 | n/a | n/a |
| `poly1305` | 40.860 | **38.386** | 44.764 | n/a | n/a |
| `blake2b` | 183.867 | **64.948** | 69.323 | n/a | n/a |
| `sha512` | **49.109** | 50.752 | 49.967 | n/a | n/a |
| `x25519` | 56.782 | **48.732** | 49.504 | n/a | n/a |

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
| _(floor: empty program)_ | _3.744_ | _106.102_ | _**109.846**_ | _64.822_ | _82.572_ | _63.929_ |
| `lcg` | 4.019 | 110.999 | **115.018** | 60.906 | 89.804 | 66.906 |
| `packet_classifier` | 3.896 | 109.816 | **113.712** | 59.417 | 95.011 | 65.646 |
| `ring_write` | 4.271 | 114.254 | **118.525** | 61.624 | 93.165 | 71.279 |
| `histogram_bins` | 4.341 | 123.447 | **127.788** | 62.429 | 112.362 | 78.782 |
| `prefix_scan` | 4.557 | 117.864 | **122.421** | 64.075 | 104.646 | 74.444 |
| `binary_search` | 4.685 | 114.092 | **118.777** | 62.349 | 96.533 | 78.353 |
| `sort_window` | 4.938 | 116.358 | **121.296** | 63.078 | 106.804 | 80.540 |
| `bloom_filter` | 5.897 | 123.525 | **129.422** | 65.423 | 103.106 | 84.325 |
| `hash_join` | 9.876 | 268.005 | **277.881** | 69.082 | 223.628 | 128.624 |
| `sieve` | 4.889 | 116.689 | **121.578** | 64.998 | 105.461 | 80.777 |
| `fib` | 4.351 | 124.689 | **129.040** | 65.360 | 92.270 | 68.698 |
| `collatz` | 4.521 | 123.859 | **128.380** | 64.957 | 97.641 | 72.977 |
| `matmul` | 6.490 | 120.453 | **126.943** | 67.143 | 108.451 | 92.606 |
| `json_parse` | 52.821 | 506.869 | **559.690** | 115.033 | 166.606 | 179.157 |
| `nbody` | 7.673 | 143.235 | **150.908** | 69.902 | 130.070 | 112.042 |
| `chacha20` | 43.153 | 348.179 | **391.332** | 104.341 | 144.465 | 126.316 |
| `poly1305` | 25.734 | 260.288 | **286.022** | 85.984 | 158.548 | 140.758 |
| `blake2b` | 42.465 | 441.737 | **484.202** | 101.589 | 148.943 | 134.712 |
| `sha512` | 37.746 | 454.610 | **492.356** | 98.545 | 143.474 | 123.295 |
| `x25519` | 43.849 | 392.602 | **436.451** | 105.286 | 1244.340 | 515.348 |

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
