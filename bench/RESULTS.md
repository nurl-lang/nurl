# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T11:43:05Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `4974c8d46e86158d2c2acc1254bcf47a3626fad6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41049371503 |
| NURL | `v0.80.0-120-g4974c8d4` |
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
| _(floor: empty program)_ | _3.441_ | _3.494_ | _3.704_ | _28.693_ | _15.607_ |
| `lcg` | **41.623** | 41.674 | 41.839 | 1814.533 | 4984.363 |
| `packet_classifier` | **58.771** | 58.900 | 59.058 | 167.554 | 4000.612 |
| `ring_write` | **44.407** | 44.766 | 45.000 | 72.910 | 6253.277 |
| `histogram_bins` | **41.663** | 42.836 | 42.743 | 69.844 | 6210.919 |
| `prefix_scan` | 23.788 | **23.695** | 24.029 | 68.259 | 4081.422 |
| `binary_search` | 41.603 | **40.368** | 42.856 | 110.897 | 6597.566 |
| `sort_window` | 28.645 | **28.446** | 28.691 | 198.467 | 12030.587 |
| `bloom_filter` | **18.603** | 19.734 | 20.251 | 2846.765 | 7094.699 |
| `hash_join` | 28.716 | **28.639** | 31.461 | 3384.901 | 7750.098 |
| `sieve` | 27.968 | 26.843 | **26.542** | 74.990 | 3105.776 |
| `fib` | **27.295** | 31.908 | 32.043 | 137.081 | 1140.313 |
| `collatz` | 14.316 | **14.244** | 14.608 | 55.108 | 681.393 |
| `matmul` | 35.848 | **35.696** | 36.083 | 75.039 | 3026.993 |
| `json_parse` | **10.240** | 13.186 | 18.683 | 41.314 | 37.492 |
| `nbody` | **26.196** | 42.154 | 27.505 | 103.857 | 2940.720 |
| `chacha20` | **9.453** | 44.567 | 36.098 | n/a | n/a |
| `poly1305` | **13.730** | 34.525 | 23.704 | n/a | n/a |
| `blake2b` | **46.419** | 67.257 | 71.488 | n/a | n/a |
| `sha512` | **49.649** | 49.802 | 51.958 | n/a | n/a |
| `x25519` | **33.619** | 51.033 | 51.550 | n/a | n/a |

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
| _(floor: empty program)_ | _7.075_ | _121.496_ | _**128.571**_ | _71.519_ | _88.582_ | _65.145_ |
| `lcg` | 6.981 | 125.201 | **132.182** | 64.302 | 90.690 | 73.892 |
| `packet_classifier` | 7.091 | 129.616 | **136.707** | 67.061 | 95.864 | 76.093 |
| `ring_write` | 17.565 | 132.724 | **150.289** | 75.827 | 96.808 | 79.466 |
| `histogram_bins` | 17.698 | 132.057 | **149.755** | 74.852 | 138.984 | 82.058 |
| `prefix_scan` | 18.091 | 131.188 | **149.279** | 77.330 | 98.838 | 77.574 |
| `binary_search` | 17.593 | 129.582 | **147.175** | 74.936 | 95.781 | 79.292 |
| `sort_window` | 17.872 | 130.688 | **148.560** | 74.730 | 104.500 | 85.549 |
| `bloom_filter` | 18.383 | 132.986 | **151.369** | 75.124 | 103.740 | 81.621 |
| `hash_join` | 21.812 | 267.024 | **288.836** | 78.539 | 219.167 | 128.342 |
| `sieve` | 17.535 | 127.510 | **145.045** | 74.184 | 105.373 | 87.253 |
| `fib` | 6.995 | 126.356 | **133.351** | 65.223 | 92.514 | 74.043 |
| `collatz` | 7.212 | 130.923 | **138.135** | 65.875 | 95.456 | 76.231 |
| `matmul` | 19.119 | 132.513 | **151.632** | 77.770 | 111.195 | 100.151 |
| `json_parse` | 54.384 | 466.833 | **521.217** | 117.626 | 166.333 | 180.865 |
| `nbody` | 20.797 | 141.901 | **162.698** | 81.483 | 132.330 | 114.211 |
| `chacha20` | 60.188 | 784.704 | **844.892** | 119.389 | 146.061 | 129.393 |
| `poly1305` | 45.961 | 513.190 | **559.151** | 104.972 | 149.856 | 141.064 |
| `blake2b` | 42.814 | 341.885 | **384.699** | 102.048 | 150.590 | 139.865 |
| `sha512` | 42.511 | 464.179 | **506.690** | 103.612 | 144.525 | 122.389 |
| `x25519` | 56.697 | 1563.373 | **1620.070** | 117.731 | 1258.829 | 517.008 |

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
