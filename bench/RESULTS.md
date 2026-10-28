# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T11:38:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `dd652819972d92ebae6248e5d168b75fb6625fa0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40680716779 |
| NURL | `v0.80.0` |
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
| _(floor: empty program)_ | _1.561_ | _1.515_ | _1.694_ | _27.603_ | _19.762_ |
| `lcg` | 39.351 | **39.348** | 39.442 | 1902.611 | 5761.056 |
| `packet_classifier` | 57.774 | **56.629** | 57.043 | 169.686 | 4570.605 |
| `ring_write` | **43.978** | 45.226 | 45.496 | 74.984 | 6727.563 |
| `histogram_bins` | **42.054** | 42.962 | 43.722 | 75.283 | 6112.332 |
| `prefix_scan` | 21.996 | **21.965** | 22.630 | 72.934 | 4731.881 |
| `binary_search` | 42.422 | **39.711** | 43.154 | 109.154 | 6233.448 |
| `sort_window` | **26.677** | 26.820 | 26.842 | 201.734 | 12518.026 |
| `bloom_filter` | **17.861** | 18.637 | 18.357 | 2905.970 | 7678.629 |
| `hash_join` | **28.517** | 29.398 | 29.912 | 3543.666 | 8442.821 |
| `sieve` | 22.011 | **19.902** | 20.968 | 77.088 | 3394.929 |
| `fib` | **25.395** | 30.054 | 32.177 | 142.913 | 1398.184 |
| `collatz` | 12.774 | **12.698** | 12.742 | 57.985 | 778.446 |
| `matmul` | 34.371 | **34.094** | 34.649 | 78.590 | 3190.177 |
| `json_parse` | **9.063** | 9.075 | 12.735 | 44.538 | 41.892 |
| `nbody` | **25.435** | 40.650 | 25.657 | 101.241 | 3193.044 |
| `chacha20` | **7.625** | 42.445 | 34.023 | n/a | n/a |
| `poly1305` | **12.745** | 32.572 | 21.501 | n/a | n/a |
| `blake2b` | **44.913** | 69.265 | 72.690 | n/a | n/a |
| `sha512` | **49.657** | 50.547 | 49.677 | n/a | n/a |
| `x25519` | **32.170** | 51.382 | 49.753 | n/a | n/a |

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
| _(floor: empty program)_ | _4.850_ | _121.114_ | _**125.964**_ | _63.557_ | _84.243_ | _61.196_ |
| `lcg` | 5.453 | 141.333 | **146.786** | 72.201 | 102.448 | 66.922 |
| `packet_classifier` | 4.952 | 134.170 | **139.122** | 65.440 | 94.058 | 60.068 |
| `ring_write` | 17.204 | 150.078 | **167.282** | 82.330 | 111.258 | 68.098 |
| `histogram_bins` | 17.160 | 151.147 | **168.307** | 89.019 | 119.184 | 77.789 |
| `prefix_scan` | 15.537 | 148.121 | **163.658** | 89.049 | 122.699 | 73.351 |
| `binary_search` | 16.730 | 141.182 | **157.912** | 83.997 | 112.802 | 74.326 |
| `sort_window` | 16.082 | 142.739 | **158.821** | 77.654 | 109.481 | 78.853 |
| `bloom_filter` | 18.279 | 155.198 | **173.477** | 85.584 | 122.792 | 73.434 |
| `hash_join` | 21.474 | 285.918 | **307.392** | 85.826 | 226.895 | 126.696 |
| `sieve` | 17.334 | 151.991 | **169.325** | 88.346 | 119.078 | 86.615 |
| `fib` | 5.865 | 158.441 | **164.306** | 76.800 | 110.923 | 66.696 |
| `collatz` | 5.760 | 154.414 | **160.174** | 71.039 | 104.240 | 67.743 |
| `matmul` | 17.686 | 155.451 | **173.137** | 81.889 | 126.408 | 80.924 |
| `json_parse` | 54.222 | 529.823 | **584.045** | 122.899 | 168.455 | 176.812 |
| `nbody` | 20.630 | 163.115 | **183.745** | 92.690 | 154.040 | 110.376 |
| `chacha20` | 63.183 | 833.076 | **896.259** | 132.600 | 154.612 | 112.206 |
| `poly1305` | 49.157 | 556.458 | **605.615** | 120.361 | 163.241 | 138.935 |
| `blake2b` | 43.703 | 425.925 | **469.628** | 117.035 | 160.711 | 132.800 |
| `sha512` | 43.534 | 506.948 | **550.482** | 108.754 | 146.447 | 116.318 |
| `x25519` | 60.142 | 1233.857 | **1293.999** | 126.767 | 1277.211 | 512.627 |

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
