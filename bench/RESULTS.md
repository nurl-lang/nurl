# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T05:48:28Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16366512 KiB |
| Commit | `91aff9715f674e34d2b104ffeb82f88f61aef30a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41009931134 |
| NURL | `v0.80.0-109-g91aff971` |
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
| _(floor: empty program)_ | _1.268_ | _1.242_ | _1.400_ | _24.500_ | _16.448_ |
| `lcg` | 37.657 | **37.600** | 37.818 | 1816.466 | 5500.181 |
| `packet_classifier` | **52.753** | 52.843 | 53.100 | 158.876 | 4194.264 |
| `ring_write` | **40.686** | 40.796 | 41.223 | 73.179 | 6406.714 |
| `histogram_bins` | 40.707 | 40.811 | **40.147** | 68.949 | 6326.428 |
| `prefix_scan` | 21.525 | 21.521 | **21.192** | 69.693 | 4499.309 |
| `binary_search` | 35.281 | **30.000** | 36.816 | 107.779 | 6746.331 |
| `sort_window` | 35.727 | **35.311** | 36.042 | 185.110 | 11478.054 |
| `bloom_filter` | **14.214** | 14.305 | 14.357 | 3043.709 | 7707.508 |
| `hash_join` | **25.284** | 25.435 | 27.035 | 3536.066 | 8046.012 |
| `sieve` | **40.370** | 41.027 | 42.280 | 90.612 | 3705.467 |
| `fib` | **25.922** | 26.893 | 26.853 | 126.164 | 1173.254 |
| `collatz` | 13.264 | **13.081** | 13.104 | 59.744 | 691.889 |
| `matmul` | **17.614** | 17.648 | 18.036 | 77.288 | 3170.037 |
| `json_parse` | **7.320** | 7.701 | 10.159 | 37.398 | 38.481 |
| `nbody` | 22.306 | 35.544 | **22.005** | 96.767 | 2402.664 |
| `chacha20` | **8.054** | 38.112 | 33.750 | n/a | n/a |
| `poly1305` | **12.874** | 34.698 | 25.913 | n/a | n/a |
| `blake2b` | **45.083** | 58.435 | 66.499 | n/a | n/a |
| `sha512` | **45.707** | 47.794 | 49.447 | n/a | n/a |
| `x25519` | **30.433** | 48.652 | 50.135 | n/a | n/a |

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
| _(floor: empty program)_ | _4.226_ | _106.759_ | _**110.985**_ | _58.037_ | _74.920_ | _55.235_ |
| `lcg` | 4.281 | 117.178 | **121.459** | 57.933 | 81.831 | 64.332 |
| `packet_classifier` | 4.331 | 119.084 | **123.415** | 57.293 | 82.458 | 62.270 |
| `ring_write` | 14.797 | 121.661 | **136.458** | 68.594 | 85.453 | 66.227 |
| `histogram_bins` | 14.907 | 122.450 | **137.357** | 68.821 | 101.974 | 75.441 |
| `prefix_scan` | 14.875 | 123.787 | **138.662** | 68.532 | 90.940 | 70.280 |
| `binary_search` | 15.299 | 123.001 | **138.300** | 70.105 | 88.833 | 72.065 |
| `sort_window` | 14.975 | 121.225 | **136.200** | 67.655 | 92.815 | 75.345 |
| `bloom_filter` | 15.639 | 126.572 | **142.211** | 70.382 | 93.854 | 71.077 |
| `hash_join` | 19.578 | 249.578 | **269.156** | 76.264 | 204.100 | 121.825 |
| `sieve` | 15.338 | 125.369 | **140.707** | 70.393 | 96.379 | 82.010 |
| `fib` | 4.807 | 124.594 | **129.401** | 62.174 | 87.103 | 68.238 |
| `collatz` | 4.992 | 127.298 | **132.290** | 63.447 | 88.620 | 68.909 |
| `matmul` | 16.654 | 128.959 | **145.613** | 72.962 | 100.852 | 90.703 |
| `json_parse` | 49.125 | 441.191 | **490.316** | 106.636 | 151.422 | 176.334 |
| `nbody` | 17.711 | 133.300 | **151.011** | 73.879 | 121.389 | 106.131 |
| `chacha20` | 54.782 | 743.334 | **798.116** | 112.229 | 134.409 | 120.154 |
| `poly1305` | 42.376 | 501.480 | **543.856** | 100.140 | 135.977 | 133.017 |
| `blake2b` | 37.909 | 367.720 | **405.629** | 95.640 | 140.916 | 129.238 |
| `sha512` | 38.070 | 448.574 | **486.644** | 95.795 | 132.057 | 113.531 |
| `x25519` | 51.179 | 1278.144 | **1329.323** | 108.311 | 1236.514 | 506.638 |

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
