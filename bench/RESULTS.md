# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T11:20:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16365632 KiB |
| Commit | `b7b7e51381d02eacc3a41f4a2cd4671e35b68616` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41195746100 |
| NURL | `v0.82.0-31-gb7b7e513` |
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
| _(floor: empty program)_ | _2.578_ | _2.477_ | _2.661_ | _25.724_ | _12.836_ |
| `lcg` | **38.854** | 39.046 | 39.025 | 1730.313 | 5116.210 |
| `packet_classifier` | 54.260 | **54.014** | 54.295 | 160.056 | 4150.250 |
| `ring_write` | **41.991** | 42.056 | 42.467 | 71.753 | 6454.408 |
| `histogram_bins` | 41.916 | **41.435** | 42.617 | 68.828 | 5827.052 |
| `prefix_scan` | 22.321 | **21.901** | 21.913 | 64.896 | 4057.642 |
| `binary_search` | 36.390 | **30.915** | 37.916 | 107.747 | 6359.883 |
| `sort_window` | 37.230 | **36.334** | 36.918 | 182.344 | 11200.615 |
| `bloom_filter` | 15.232 | **15.088** | 15.111 | 2816.740 | 7001.185 |
| `hash_join` | 25.332 | **24.935** | 27.893 | 3460.186 | 7274.192 |
| `sieve` | **35.363** | 39.574 | 39.323 | 89.009 | 3095.884 |
| `fib` | **27.119** | 27.638 | 27.871 | 126.112 | 971.325 |
| `collatz` | 14.609 | 14.069 | **14.052** | 59.671 | 631.305 |
| `matmul` | 18.342 | **18.335** | 18.424 | 73.160 | 2853.796 |
| `json_parse` | **8.200** | 10.362 | 13.877 | 35.156 | 33.562 |
| `nbody` | **23.027** | 36.579 | 23.094 | 94.216 | 2443.118 |
| `chacha20` | **8.801** | 39.252 | 34.542 | n/a | n/a |
| `poly1305` | **13.314** | 35.684 | 26.801 | n/a | n/a |
| `blake2b` | **46.472** | 56.197 | 65.913 | n/a | n/a |
| `sha512` | 47.081 | **46.038** | 50.692 | n/a | n/a |
| `x25519` | **31.334** | 50.275 | 50.967 | n/a | n/a |

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
| _(floor: empty program)_ | _5.460_ | _99.906_ | _**105.366**_ | _55.842_ | _67.651_ | _52.444_ |
| `lcg` | 5.847 | 112.882 | **118.729** | 55.195 | 75.599 | 61.348 |
| `packet_classifier` | 5.869 | 113.330 | **119.199** | 57.598 | 78.902 | 62.004 |
| `ring_write` | 14.792 | 115.425 | **130.217** | 65.444 | 78.888 | 61.390 |
| `histogram_bins` | 15.285 | 120.708 | **135.993** | 66.032 | 122.803 | 68.927 |
| `prefix_scan` | 15.126 | 116.849 | **131.975** | 65.000 | 82.789 | 67.054 |
| `binary_search` | 15.421 | 115.857 | **131.278** | 66.828 | 78.682 | 68.397 |
| `sort_window` | 15.476 | 117.072 | **132.548** | 65.056 | 86.413 | 72.057 |
| `bloom_filter` | 15.825 | 117.409 | **133.234** | 65.538 | 85.884 | 69.629 |
| `hash_join` | 19.011 | 239.161 | **258.172** | 69.916 | 188.238 | 112.554 |
| `sieve` | 15.079 | 113.838 | **128.917** | 65.858 | 86.981 | 72.938 |
| `fib` | 5.875 | 112.006 | **117.881** | 55.286 | 74.906 | 61.117 |
| `collatz` | 6.015 | 115.599 | **121.614** | 56.587 | 79.635 | 63.293 |
| `matmul` | 15.658 | 116.320 | **131.978** | 65.142 | 88.949 | 82.302 |
| `json_parse` | 45.541 | 398.572 | **444.113** | 97.114 | 135.305 | 169.945 |
| `nbody` | 16.832 | 121.129 | **137.961** | 66.657 | 109.893 | 97.956 |
| `chacha20` | 53.029 | 718.145 | **771.174** | 106.068 | 127.538 | 109.681 |
| `poly1305` | 41.965 | 477.473 | **519.438** | 92.097 | 132.491 | 124.197 |
| `blake2b` | 35.839 | 310.966 | **346.805** | 88.145 | 127.906 | 120.793 |
| `sha512` | 35.982 | 410.274 | **446.256** | 87.845 | 123.184 | 104.554 |
| `x25519` | 48.630 | 1452.427 | **1501.057** | 100.362 | 1168.688 | 487.764 |

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
