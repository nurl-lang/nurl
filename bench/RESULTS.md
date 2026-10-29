# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T09:55:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367516 KiB |
| Commit | `4f56f2067f2b95fc3ad4036e658d6ba49162e1c8` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40852590062 |
| NURL | `v0.80.0-51-g4f56f206` |
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
| _(floor: empty program)_ | _1.544_ | _1.539_ | _1.733_ | _23.552_ | _17.784_ |
| `lcg` | **39.057** | 39.130 | 39.383 | 1814.253 | 5136.170 |
| `packet_classifier` | 56.325 | **56.296** | 56.449 | 163.177 | 4410.331 |
| `ring_write` | **42.387** | 42.970 | 42.484 | 67.325 | 6484.899 |
| `histogram_bins` | **39.549** | 40.705 | 40.866 | 67.940 | 6185.976 |
| `prefix_scan` | 21.784 | **21.783** | 22.011 | 66.334 | 4567.467 |
| `binary_search` | 39.689 | **38.186** | 40.983 | 107.299 | 6048.593 |
| `sort_window` | **26.614** | 26.643 | 26.818 | 199.574 | 12037.611 |
| `bloom_filter` | **16.700** | 17.914 | 18.361 | 2882.755 | 8065.042 |
| `hash_join` | **26.890** | 27.878 | 29.203 | 3458.807 | 8454.112 |
| `sieve` | 24.471 | **23.717** | 23.912 | 70.989 | 3285.582 |
| `fib` | **25.219** | 29.912 | 30.074 | 132.670 | 1374.671 |
| `collatz` | **12.244** | 12.317 | 12.512 | 51.899 | 738.968 |
| `matmul` | 33.721 | **33.542** | 33.703 | 77.272 | 3137.775 |
| `json_parse` | **8.426** | 8.729 | 11.833 | 36.874 | 38.686 |
| `nbody` | 25.255 | 39.712 | **25.237** | 100.870 | 3151.339 |
| `chacha20` | **7.362** | 40.457 | 33.670 | n/a | n/a |
| `poly1305` | **11.646** | 31.887 | 21.228 | n/a | n/a |
| `blake2b` | **43.903** | 65.041 | 69.182 | n/a | n/a |
| `sha512` | **47.676** | 50.576 | 49.678 | n/a | n/a |
| `x25519` | **31.634** | 48.621 | 49.322 | n/a | n/a |

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
| _(floor: empty program)_ | _4.701_ | _120.520_ | _**125.221**_ | _64.587_ | _84.789_ | _64.510_ |
| `lcg` | 4.789 | 131.614 | **136.403** | 64.131 | 93.142 | 70.675 |
| `packet_classifier` | 4.946 | 131.393 | **136.339** | 64.831 | 94.699 | 73.426 |
| `ring_write` | 15.804 | 134.315 | **150.119** | 74.545 | 96.239 | 74.097 |
| `histogram_bins` | 15.946 | 139.222 | **155.168** | 76.150 | 114.186 | 83.518 |
| `prefix_scan` | 16.058 | 135.732 | **151.790** | 74.507 | 102.583 | 77.050 |
| `binary_search` | 15.681 | 133.890 | **149.571** | 74.765 | 98.381 | 79.800 |
| `sort_window` | 16.129 | 136.005 | **152.134** | 75.235 | 108.201 | 84.555 |
| `bloom_filter` | 16.691 | 138.088 | **154.779** | 75.109 | 106.162 | 80.556 |
| `hash_join` | 20.279 | 269.339 | **289.618** | 79.004 | 225.050 | 126.730 |
| `sieve` | 16.139 | 133.952 | **150.091** | 74.781 | 106.976 | 86.403 |
| `fib` | 5.028 | 134.117 | **139.145** | 65.154 | 98.013 | 73.975 |
| `collatz` | 5.147 | 134.583 | **139.730** | 65.622 | 95.728 | 73.715 |
| `matmul` | 17.402 | 135.557 | **152.959** | 75.649 | 111.690 | 95.958 |
| `json_parse` | 51.018 | 482.286 | **533.304** | 111.924 | 166.914 | 177.585 |
| `nbody` | 18.672 | 141.767 | **160.439** | 77.546 | 132.696 | 110.151 |
| `chacha20` | 58.676 | 761.729 | **820.405** | 119.611 | 146.215 | 122.806 |
| `poly1305` | 45.000 | 520.336 | **565.336** | 106.109 | 146.303 | 139.270 |
| `blake2b` | 39.841 | 380.891 | **420.732** | 100.428 | 151.958 | 134.092 |
| `sha512` | 39.704 | 478.409 | **518.113** | 99.592 | 144.958 | 119.243 |
| `x25519` | 55.073 | 1303.129 | **1358.202** | 115.209 | 1228.085 | 512.361 |

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
