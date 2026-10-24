# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-24T09:55:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a02dbce43d58e6a56e96f1ddbdf5fe7654291c63` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40083465235 |
| NURL | `v0.77.2-38-ga02dbce4` |
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
| _(floor: empty program)_ | _1.458_ | _1.396_ | _1.622_ | _22.727_ | _16.994_ |
| `lcg` | 38.986 | **38.963** | 39.129 | 1934.040 | 5071.591 |
| `packet_classifier` | 56.166 | **56.147** | 56.258 | 160.790 | 4653.330 |
| `ring_write` | 42.183 | **42.046** | 42.200 | 65.048 | 6342.947 |
| `histogram_bins` | 40.545 | **40.535** | 40.745 | 65.612 | 6072.934 |
| `prefix_scan` | **21.578** | 21.684 | 21.919 | 65.291 | 4830.938 |
| `binary_search` | **38.040** | 38.358 | 40.842 | 106.809 | 6727.503 |
| `sort_window` | 26.607 | **26.589** | 26.820 | 200.135 | 11503.164 |
| `bloom_filter` | **15.518** | 18.030 | 18.379 | 2830.914 | 7478.561 |
| `hash_join` | **26.863** | 27.962 | 29.127 | 3390.311 | 8361.051 |
| `sieve` | 18.938 | 18.028 | **17.849** | 65.628 | 3275.847 |
| `fib` | **29.726** | 29.779 | 29.971 | 130.918 | 1372.462 |
| `collatz` | 12.248 | **12.233** | 12.472 | 51.383 | 739.752 |
| `matmul` | 33.436 | **33.305** | 33.439 | 75.097 | 3144.615 |
| `json_parse` | **8.202** | 8.634 | 11.899 | 35.817 | 39.429 |
| `nbody` | **25.277** | 39.804 | 25.335 | 101.785 | 3048.165 |
| `chacha20` | **7.238** | 41.981 | 33.580 | n/a | n/a |
| `poly1305` | **11.653** | 31.732 | 21.070 | n/a | n/a |
| `blake2b` | **43.623** | 65.182 | 69.160 | n/a | n/a |
| `sha512` | **46.653** | 50.552 | 49.625 | n/a | n/a |
| `x25519` | **44.282** | 48.940 | 49.539 | n/a | n/a |

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
| _(floor: empty program)_ | _4.218_ | _107.948_ | _**112.166**_ | _59.807_ | _75.715_ | _52.153_ |
| `lcg` | 4.445 | 120.736 | **125.181** | 60.103 | 85.973 | 56.543 |
| `packet_classifier` | 4.529 | 119.095 | **123.624** | 59.307 | 86.834 | 57.225 |
| `ring_write` | 13.672 | 123.452 | **137.124** | 69.583 | 89.314 | 58.578 |
| `histogram_bins` | 13.737 | 125.865 | **139.602** | 70.061 | 107.134 | 65.778 |
| `prefix_scan` | 13.804 | 125.444 | **139.248** | 69.899 | 96.176 | 62.300 |
| `binary_search` | 13.761 | 125.440 | **139.201** | 70.376 | 93.281 | 63.505 |
| `sort_window` | 14.088 | 126.270 | **140.358** | 70.340 | 100.024 | 67.973 |
| `bloom_filter` | 14.940 | 132.722 | **147.662** | 74.082 | 103.486 | 65.856 |
| `hash_join` | 18.340 | 269.011 | **287.351** | 77.407 | 217.677 | 111.876 |
| `sieve` | 13.947 | 124.365 | **138.312** | 70.580 | 101.918 | 68.607 |
| `fib` | 4.587 | 120.129 | **124.716** | 62.302 | 87.594 | 58.667 |
| `collatz` | 4.681 | 123.627 | **128.308** | 60.836 | 91.448 | 58.813 |
| `matmul` | 15.518 | 127.482 | **143.000** | 73.394 | 105.706 | 78.204 |
| `json_parse` | 47.559 | 503.070 | **550.629** | 107.647 | 161.541 | 154.212 |
| `nbody` | 16.776 | 136.630 | **153.406** | 73.911 | 126.904 | 94.416 |
| `chacha20` | 55.712 | 824.151 | **879.863** | 112.340 | 140.821 | 103.853 |
| `poly1305` | 41.131 | 511.379 | **552.510** | 98.029 | 141.272 | 118.083 |
| `blake2b` | 36.798 | 379.447 | **416.245** | 93.562 | 146.097 | 115.312 |
| `sha512` | 37.032 | 476.640 | **513.672** | 95.504 | 138.640 | 98.720 |
| `x25519` | 37.816 | 833.623 | **871.439** | 96.380 | 1232.416 | 494.276 |

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
