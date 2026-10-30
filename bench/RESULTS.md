# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T10:46:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `2a2c4b4d173f42739db917d57097ddc54263d32d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41042492564 |
| NURL | `v0.80.0-118-g2a2c4b4d` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.4 |
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
| _(floor: empty program)_ | _1.564_ | _1.498_ | _1.728_ | _22.777_ | _17.435_ |
| `lcg` | 39.118 | **39.098** | 39.313 | 1819.892 | 5130.009 |
| `packet_classifier` | 56.267 | **56.242** | 56.391 | 162.293 | 4357.834 |
| `ring_write` | 42.259 | **42.190** | 42.406 | 66.597 | 6446.270 |
| `histogram_bins` | **39.562** | 40.671 | 40.857 | 66.759 | 6090.648 |
| `prefix_scan` | **21.718** | 21.724 | 21.906 | 66.489 | 4555.280 |
| `binary_search` | 39.819 | **38.176** | 40.998 | 106.494 | 6671.756 |
| `sort_window` | 26.735 | **26.572** | 26.875 | 198.448 | 11312.496 |
| `bloom_filter` | **16.661** | 17.861 | 18.408 | 2842.801 | 7865.965 |
| `hash_join` | **26.901** | 27.993 | 29.190 | 3472.571 | 8333.151 |
| `sieve` | 24.531 | **23.410** | 23.674 | 70.334 | 3567.458 |
| `fib` | **25.170** | 29.783 | 29.872 | 130.086 | 1351.792 |
| `collatz` | 12.278 | **12.202** | 12.492 | 49.108 | 734.358 |
| `matmul` | 33.521 | **33.380** | 33.785 | 76.040 | 3106.392 |
| `json_parse` | **8.433** | 8.673 | 11.810 | 34.455 | 38.214 |
| `nbody` | 25.305 | 39.701 | **25.264** | 101.933 | 3178.497 |
| `chacha20` | **7.427** | 40.378 | 33.559 | n/a | n/a |
| `poly1305` | **11.655** | 31.804 | 21.176 | n/a | n/a |
| `blake2b` | **43.918** | 65.049 | 69.092 | n/a | n/a |
| `sha512` | **47.266** | 50.536 | 49.409 | n/a | n/a |
| `x25519` | **31.524** | 48.571 | 49.424 | n/a | n/a |

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
| _(floor: empty program)_ | _4.825_ | _119.206_ | _**124.031**_ | _64.869_ | _80.439_ | _62.231_ |
| `lcg` | 4.834 | 128.718 | **133.552** | 63.936 | 91.780 | 70.553 |
| `packet_classifier` | 4.969 | 129.504 | **134.473** | 64.159 | 93.092 | 71.732 |
| `ring_write` | 15.629 | 131.532 | **147.161** | 73.200 | 94.368 | 73.608 |
| `histogram_bins` | 15.739 | 132.086 | **147.825** | 73.428 | 111.159 | 80.350 |
| `prefix_scan` | 15.883 | 133.163 | **149.046** | 74.119 | 99.668 | 76.878 |
| `binary_search` | 15.927 | 131.730 | **147.657** | 73.581 | 95.468 | 78.425 |
| `sort_window` | 15.997 | 133.284 | **149.281** | 73.903 | 105.189 | 83.395 |
| `bloom_filter` | 16.620 | 134.774 | **151.394** | 74.124 | 103.555 | 78.652 |
| `hash_join` | 19.904 | 265.568 | **285.472** | 77.927 | 220.366 | 123.861 |
| `sieve` | 15.959 | 132.204 | **148.163** | 74.146 | 105.924 | 84.412 |
| `fib` | 5.037 | 129.913 | **134.950** | 64.623 | 92.865 | 73.180 |
| `collatz` | 5.157 | 132.294 | **137.451** | 64.591 | 93.818 | 74.077 |
| `matmul` | 17.271 | 132.453 | **149.724** | 74.782 | 107.864 | 94.713 |
| `json_parse` | 50.724 | 475.846 | **526.570** | 110.306 | 162.778 | 174.190 |
| `nbody` | 18.402 | 138.667 | **157.069** | 76.867 | 129.547 | 109.026 |
| `chacha20` | 57.787 | 755.717 | **813.504** | 116.866 | 142.626 | 122.048 |
| `poly1305` | 44.108 | 514.425 | **558.533** | 103.114 | 145.183 | 136.428 |
| `blake2b` | 39.878 | 376.110 | **415.988** | 98.799 | 149.590 | 131.317 |
| `sha512` | 39.373 | 473.940 | **513.313** | 97.825 | 141.674 | 117.511 |
| `x25519` | 54.001 | 1292.652 | **1346.653** | 113.561 | 1217.425 | 512.504 |

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
