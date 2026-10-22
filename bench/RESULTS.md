# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-22T04:30:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `79a28f8c08cfb5a7b5150a98c7f77be6a4cbe6e7` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39722334926 |
| NURL | `v0.76.0-28-g79a28f8c` |
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
| _(floor: empty program)_ | _1.262_ | _1.231_ | _1.419_ | _16.988_ | _12.119_ |
| `lcg` | **30.219** | 30.278 | 30.365 | 1144.223 | 3068.918 |
| `packet_classifier` | **43.422** | 43.524 | 43.627 | 135.227 | 2765.280 |
| `ring_write` | 30.039 | **30.032** | 30.168 | 50.387 | 3787.387 |
| `histogram_bins` | **30.047** | 30.120 | 30.226 | 50.309 | 3562.723 |
| `prefix_scan` | **16.766** | 16.804 | 16.948 | 48.494 | 2489.715 |
| `binary_search` | 14.879 | **14.809** | 14.989 | 66.475 | 3599.952 |
| `sort_window` | **20.478** | 20.499 | 20.537 | 128.634 | 6118.920 |
| `bloom_filter` | 9.033 | 8.978 | **8.899** | 1652.089 | 4360.094 |
| `hash_join` | **16.225** | 16.822 | 17.992 | 1989.876 | 4515.015 |
| `sieve` | 14.527 | **13.945** | 14.040 | 45.412 | 1732.900 |
| `fib` | 18.805 | **18.527** | 18.619 | 75.014 | 664.592 |
| `collatz` | 9.041 | **8.937** | 9.170 | 35.127 | 407.864 |
| `matmul` | 20.150 | 19.930 | **19.785** | 51.927 | 1795.358 |
| `json_parse` | **4.985** | 5.251 | 6.644 | 23.569 | 23.345 |
| `nbody` | **16.565** | 30.628 | 17.309 | 56.357 | 1456.752 |
| `chacha20` | **6.566** | 19.046 | 18.571 | n/a | n/a |
| `poly1305` | **15.114** | 25.833 | 15.223 | n/a | n/a |
| `blake2b` | **25.406** | 40.896 | 47.588 | n/a | n/a |
| `sha512` | **30.362** | 31.766 | 32.566 | n/a | n/a |
| `x25519` | **26.445** | 29.837 | 31.156 | n/a | n/a |

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
| _(floor: empty program)_ | _3.948_ | _92.897_ | _**96.845**_ | _53.578_ | _67.152_ | _51.950_ |
| `lcg` | 3.767 | 95.144 | **98.911** | 51.404 | 76.226 | 59.843 |
| `packet_classifier` | 3.976 | 99.770 | **103.746** | 51.739 | 77.697 | 61.156 |
| `ring_write` | 9.813 | 98.312 | **108.125** | 56.498 | 76.972 | 61.355 |
| `histogram_bins` | 9.831 | 99.044 | **108.875** | 56.278 | 85.295 | 66.237 |
| `prefix_scan` | 9.709 | 101.140 | **110.849** | 57.516 | 150.024 | 103.165 |
| `binary_search` | 9.607 | 94.658 | **104.265** | 55.211 | 74.261 | 59.886 |
| `sort_window` | 10.153 | 100.372 | **110.525** | 57.688 | 86.965 | 68.062 |
| `bloom_filter` | 9.567 | 95.911 | **105.478** | 54.996 | 79.405 | 61.902 |
| `hash_join` | 12.079 | 179.548 | **191.627** | 59.623 | 144.699 | 93.990 |
| `sieve` | 9.280 | 90.524 | **99.804** | 53.077 | 76.183 | 69.039 |
| `fib` | 3.739 | 91.520 | **95.259** | 48.208 | 69.315 | 56.241 |
| `collatz` | 3.859 | 94.335 | **98.194** | 48.816 | 73.369 | 58.739 |
| `matmul` | 10.415 | 97.371 | **107.786** | 56.196 | 83.401 | 73.523 |
| `json_parse` | 29.123 | 307.217 | **336.340** | 74.697 | 113.943 | 126.833 |
| `nbody` | 10.715 | 98.159 | **108.874** | 55.283 | 92.820 | 79.259 |
| `chacha20` | 27.900 | 475.045 | **502.945** | 71.786 | 101.165 | 92.969 |
| `poly1305` | 19.371 | 182.730 | **202.101** | 64.056 | 100.473 | 98.264 |
| `blake2b` | 22.004 | 234.417 | **256.421** | 65.802 | 102.665 | 98.412 |
| `sha512` | 22.545 | 298.205 | **320.750** | 69.323 | 104.253 | 91.754 |
| `x25519` | 21.966 | 495.059 | **517.025** | 66.358 | 732.320 | 329.507 |

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
