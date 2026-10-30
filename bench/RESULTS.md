# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T19:33:08Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366636 KiB |
| Commit | `26cb21fb14a4f537978dc516651fdbf53558f7b0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41115371656 |
| NURL | `v0.81.0-10-g26cb21fb` |
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
| _(floor: empty program)_ | _3.349_ | _3.268_ | _3.531_ | _26.946_ | _14.974_ |
| `lcg` | 41.281 | **41.084** | 41.327 | 1805.087 | 4961.179 |
| `packet_classifier` | **58.196** | 58.445 | 58.525 | 167.791 | 4037.206 |
| `ring_write` | 44.325 | **44.163** | 44.469 | 70.310 | 6193.722 |
| `histogram_bins` | **41.575** | 42.724 | 42.802 | 69.909 | 5620.164 |
| `prefix_scan` | 23.649 | **23.510** | 23.857 | 68.053 | 4222.894 |
| `binary_search` | 41.630 | **40.299** | 43.139 | 110.551 | 6151.856 |
| `sort_window` | 28.713 | **28.479** | 28.795 | 198.332 | 12517.143 |
| `bloom_filter` | **18.504** | 19.722 | 20.240 | 2943.548 | 7067.417 |
| `hash_join` | 28.750 | **28.515** | 31.126 | 3416.110 | 7689.220 |
| `sieve` | 24.341 | **24.153** | 24.211 | 73.812 | 3076.988 |
| `fib` | **27.641** | 32.042 | 31.955 | 137.560 | 1132.205 |
| `collatz` | 14.243 | **14.199** | 14.387 | 55.646 | 707.301 |
| `matmul` | 35.546 | **35.514** | 35.741 | 74.959 | 3005.827 |
| `json_parse` | **10.388** | 13.380 | 18.520 | 39.443 | 36.926 |
| `nbody` | **26.072** | 41.724 | 27.282 | 102.646 | 2952.914 |
| `chacha20` | **9.217** | 43.367 | 35.717 | n/a | n/a |
| `poly1305` | **13.419** | 33.891 | 23.211 | n/a | n/a |
| `blake2b` | **45.874** | 66.683 | 71.201 | n/a | n/a |
| `sha512` | **49.347** | 49.488 | 51.486 | n/a | n/a |
| `x25519` | **33.635** | 50.522 | 51.287 | n/a | n/a |

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
| _(floor: empty program)_ | _6.580_ | _115.244_ | _**121.824**_ | _65.618_ | _79.948_ | _63.324_ |
| `lcg` | 6.721 | 124.935 | **131.656** | 63.912 | 90.631 | 72.377 |
| `packet_classifier` | 6.877 | 128.090 | **134.967** | 64.713 | 93.564 | 73.231 |
| `ring_write` | 17.331 | 129.089 | **146.420** | 74.141 | 94.287 | 74.493 |
| `histogram_bins` | 17.474 | 134.295 | **151.769** | 74.577 | 137.368 | 80.558 |
| `prefix_scan` | 17.457 | 129.215 | **146.672** | 74.196 | 101.832 | 76.622 |
| `binary_search` | 17.842 | 129.847 | **147.689** | 74.660 | 94.303 | 78.176 |
| `sort_window` | 17.691 | 132.230 | **149.921** | 75.026 | 105.990 | 84.223 |
| `bloom_filter` | 18.492 | 133.476 | **151.968** | 75.851 | 103.537 | 80.376 |
| `hash_join` | 21.699 | 268.562 | **290.261** | 78.467 | 218.712 | 124.432 |
| `sieve` | 17.638 | 130.077 | **147.715** | 74.803 | 105.101 | 86.096 |
| `fib` | 6.848 | 126.162 | **133.010** | 64.025 | 91.943 | 73.849 |
| `collatz` | 7.077 | 128.676 | **135.753** | 64.267 | 94.085 | 80.907 |
| `matmul` | 19.009 | 129.248 | **148.257** | 76.969 | 109.733 | 94.780 |
| `json_parse` | 52.913 | 460.364 | **513.277** | 112.031 | 161.803 | 175.953 |
| `nbody` | 20.153 | 136.667 | **156.820** | 77.083 | 128.107 | 109.874 |
| `chacha20` | 59.277 | 830.548 | **889.825** | 118.301 | 144.330 | 124.139 |
| `poly1305` | 45.610 | 519.902 | **565.512** | 104.504 | 149.866 | 138.212 |
| `blake2b` | 40.953 | 340.451 | **381.404** | 99.944 | 148.609 | 132.512 |
| `sha512` | 41.356 | 462.004 | **503.360** | 101.179 | 142.196 | 119.849 |
| `x25519` | 55.672 | 1555.430 | **1611.102** | 114.014 | 1254.988 | 517.833 |

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
