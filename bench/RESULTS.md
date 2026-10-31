# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T13:10:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `83ef51f13baa5a1f13b3ecaf85a94911b47fbb2f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41203324487 |
| NURL | `v0.82.0-45-g83ef51f1` |
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
| _(floor: empty program)_ | _2.856_ | _2.687_ | _2.739_ | _28.341_ | _14.221_ |
| `lcg` | 39.497 | **39.366** | 41.338 | 1753.577 | 5082.648 |
| `packet_classifier` | **54.494** | 54.547 | 54.737 | 160.742 | 4239.937 |
| `ring_write` | 42.680 | **42.117** | 43.495 | 75.012 | 6442.256 |
| `histogram_bins` | 42.149 | **41.533** | 42.695 | 72.030 | 5854.943 |
| `prefix_scan` | 22.584 | 22.504 | **22.340** | 66.765 | 4144.609 |
| `binary_search` | 37.246 | **31.592** | 38.647 | 108.763 | 5971.221 |
| `sort_window` | 37.702 | **36.730** | 37.436 | 184.363 | 11703.634 |
| `bloom_filter` | 15.542 | 15.420 | **15.292** | 2845.475 | 7068.645 |
| `hash_join` | 26.505 | **26.482** | 29.864 | 3498.351 | 7276.123 |
| `sieve` | 37.572 | **37.431** | 37.515 | 92.697 | 3368.693 |
| `fib` | **27.555** | 28.337 | 28.436 | 144.284 | 984.565 |
| `collatz` | 14.720 | **14.470** | 14.667 | 64.951 | 639.392 |
| `matmul` | **19.159** | 20.687 | 20.901 | 75.801 | 2857.057 |
| `json_parse` | **8.631** | 10.814 | 14.876 | 38.535 | 34.834 |
| `nbody` | **22.994** | 37.991 | 23.208 | 95.464 | 2463.080 |
| `chacha20` | **7.404** | 39.571 | 35.042 | n/a | n/a |
| `poly1305` | **14.095** | 35.922 | 27.492 | n/a | n/a |
| `blake2b` | **46.665** | 57.026 | 68.550 | n/a | n/a |
| `sha512` | 47.555 | **46.744** | 51.001 | n/a | n/a |
| `x25519` | **32.006** | 52.803 | 51.322 | n/a | n/a |

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
| _(floor: empty program)_ | _5.819_ | _110.304_ | _**116.123**_ | _58.866_ | _72.276_ | _57.677_ |
| `lcg` | 5.966 | 122.135 | **128.101** | 59.577 | 85.546 | 65.119 |
| `packet_classifier` | 6.446 | 132.845 | **139.291** | 61.026 | 86.220 | 67.524 |
| `ring_write` | 15.663 | 124.669 | **140.332** | 71.353 | 84.764 | 70.105 |
| `histogram_bins` | 15.763 | 126.428 | **142.191** | 68.246 | 127.565 | 74.568 |
| `prefix_scan` | 15.785 | 122.967 | **138.752** | 68.264 | 88.376 | 68.245 |
| `binary_search` | 15.807 | 127.203 | **143.010** | 68.676 | 88.308 | 72.487 |
| `sort_window` | 16.273 | 124.644 | **140.917** | 67.975 | 92.246 | 73.701 |
| `bloom_filter` | 17.998 | 127.086 | **145.084** | 71.941 | 93.152 | 72.266 |
| `hash_join` | 19.340 | 244.259 | **263.599** | 72.774 | 194.807 | 116.214 |
| `sieve` | 15.681 | 127.789 | **143.470** | 69.357 | 98.956 | 76.910 |
| `fib` | 6.260 | 122.141 | **128.401** | 60.613 | 81.429 | 63.095 |
| `collatz` | 6.159 | 124.030 | **130.189** | 59.907 | 81.424 | 65.250 |
| `matmul` | 18.812 | 149.541 | **168.353** | 72.015 | 96.571 | 88.477 |
| `json_parse` | 47.479 | 419.047 | **466.526** | 104.189 | 147.083 | 165.488 |
| `nbody` | 17.724 | 126.648 | **144.372** | 70.599 | 115.799 | 100.816 |
| `chacha20` | 53.349 | 801.928 | **855.277** | 107.990 | 137.784 | 116.487 |
| `poly1305` | 42.802 | 324.720 | **367.522** | 96.448 | 139.125 | 132.313 |
| `blake2b` | 36.378 | 314.492 | **350.870** | 90.701 | 135.495 | 132.562 |
| `sha512` | 37.693 | 419.896 | **457.589** | 94.626 | 128.359 | 119.374 |
| `x25519` | 50.235 | 1469.514 | **1519.749** | 105.007 | 1179.855 | 498.091 |

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
