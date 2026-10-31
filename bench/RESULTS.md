# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T12:19:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `085a8c603c8819e3ebf2c66305f8da6abb8b54bb` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41199649048 |
| NURL | `v0.82.0-39-g085a8c60` |
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
| _(floor: empty program)_ | _2.718_ | _2.653_ | _2.818_ | _18.151_ | _10.099_ |
| `lcg` | 30.766 | **29.584** | 31.686 | 1116.712 | 2858.838 |
| `packet_classifier` | 42.295 | 44.332 | **41.859** | 126.450 | 2360.494 |
| `ring_write` | 29.840 | **29.561** | 29.604 | 49.258 | 3317.526 |
| `histogram_bins` | 29.518 | **29.466** | 29.877 | 49.450 | 3068.434 |
| `prefix_scan` | 17.961 | **17.785** | 17.870 | 47.925 | 2206.044 |
| `binary_search` | 15.896 | **15.510** | 16.278 | 67.694 | 3454.073 |
| `sort_window` | 21.822 | **21.051** | 21.395 | 131.670 | 6274.649 |
| `bloom_filter` | 10.359 | **10.251** | 10.375 | 1568.526 | 4145.613 |
| `hash_join` | 17.443 | **17.352** | 20.030 | 1889.381 | 4253.590 |
| `sieve` | 16.467 | **16.234** | 16.419 | 51.209 | 1636.869 |
| `fib` | 20.378 | **20.049** | 20.304 | 77.424 | 545.853 |
| `collatz` | 10.511 | **10.464** | 10.583 | 39.575 | 365.948 |
| `matmul` | **21.581** | 21.599 | 21.788 | 53.093 | 1650.755 |
| `json_parse` | **6.252** | 8.349 | 11.758 | 28.075 | 22.647 |
| `nbody` | **16.668** | 25.316 | 18.002 | 57.837 | 1371.497 |
| `chacha20` | **7.019** | 21.112 | 20.559 | n/a | n/a |
| `poly1305` | **10.067** | 28.468 | 17.505 | n/a | n/a |
| `blake2b` | **28.875** | 45.143 | 50.579 | n/a | n/a |
| `sha512` | 32.669 | **32.185** | 33.924 | n/a | n/a |
| `x25519` | **20.651** | 31.826 | 31.994 | n/a | n/a |

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
| _(floor: empty program)_ | _5.074_ | _86.079_ | _**91.153**_ | _47.996_ | _60.378_ | _49.181_ |
| `lcg` | 5.333 | 92.897 | **98.230** | 48.158 | 68.129 | 55.570 |
| `packet_classifier` | 5.241 | 94.103 | **99.344** | 48.817 | 74.996 | 57.175 |
| `ring_write` | 11.736 | 98.955 | **110.691** | 55.890 | 72.704 | 58.228 |
| `histogram_bins` | 11.564 | 96.625 | **108.189** | 53.850 | 92.330 | 71.267 |
| `prefix_scan` | 11.221 | 96.800 | **108.021** | 54.693 | 72.432 | 60.365 |
| `binary_search` | 11.940 | 99.568 | **111.508** | 56.669 | 73.620 | 61.280 |
| `sort_window` | 11.395 | 96.956 | **108.351** | 53.822 | 76.058 | 63.339 |
| `bloom_filter` | 11.714 | 99.939 | **111.653** | 56.794 | 80.402 | 66.095 |
| `hash_join` | 14.093 | 176.345 | **190.438** | 59.838 | 146.794 | 144.373 |
| `sieve` | 11.727 | 103.677 | **115.404** | 57.491 | 81.120 | 68.266 |
| `fib` | 5.569 | 97.692 | **103.261** | 51.221 | 69.512 | 60.340 |
| `collatz` | 5.623 | 99.068 | **104.691** | 50.211 | 80.252 | 58.860 |
| `matmul` | 11.491 | 96.990 | **108.481** | 57.099 | 84.288 | 75.741 |
| `json_parse` | 31.349 | 288.560 | **319.909** | 79.737 | 111.116 | 128.270 |
| `nbody` | 13.179 | 107.564 | **120.743** | 58.954 | 89.120 | 86.388 |
| `chacha20` | 34.635 | 503.102 | **537.737** | 81.670 | 106.353 | 93.264 |
| `poly1305` | 29.294 | 227.859 | **257.153** | 76.498 | 104.247 | 105.910 |
| `blake2b` | 24.460 | 214.996 | **239.456** | 69.187 | 102.106 | 102.028 |
| `sha512` | 26.526 | 287.894 | **314.420** | 74.990 | 108.761 | 95.029 |
| `x25519` | 32.148 | 872.129 | **904.277** | 78.221 | 717.409 | 330.709 |

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
