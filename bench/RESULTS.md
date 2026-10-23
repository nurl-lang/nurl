# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T23:19:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c35b2f3144a9cab6e411ca8e4d5a9b1c7c465562` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40038384468 |
| NURL | `v0.77.2-27-gc35b2f31` |
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
| _(floor: empty program)_ | _1.496_ | _1.452_ | _1.661_ | _26.123_ | _18.134_ |
| `lcg` | 39.219 | **39.155** | 39.413 | 1933.312 | 5113.572 |
| `packet_classifier` | **56.190** | 56.389 | 56.505 | 163.726 | 4321.697 |
| `ring_write` | 42.366 | **42.250** | 42.441 | 67.771 | 6700.212 |
| `histogram_bins` | 40.759 | **40.757** | 40.871 | 67.327 | 6095.775 |
| `prefix_scan` | 21.799 | **21.767** | 22.054 | 66.509 | 4887.089 |
| `binary_search` | 38.328 | **38.277** | 40.969 | 106.746 | 6393.108 |
| `sort_window` | 26.778 | **26.668** | 26.834 | 197.881 | 12172.149 |
| `bloom_filter` | **15.323** | 17.783 | 18.287 | 2840.600 | 7502.926 |
| `hash_join` | **26.969** | 27.950 | 29.261 | 3417.048 | 8631.498 |
| `sieve` | 20.665 | **18.223** | 18.551 | 65.313 | 3372.343 |
| `fib` | **29.670** | 29.724 | 29.863 | 132.379 | 1359.246 |
| `collatz` | 12.415 | **12.195** | 12.501 | 49.984 | 740.856 |
| `matmul` | **33.460** | 33.612 | 33.631 | 76.744 | 3094.675 |
| `json_parse` | **8.105** | 8.549 | 11.740 | 36.710 | 38.894 |
| `nbody` | **25.309** | 39.886 | 25.354 | 102.827 | 3180.830 |
| `chacha20` | **7.584** | 40.253 | 33.670 | n/a | n/a |
| `poly1305` | 23.339 | 31.852 | **21.120** | n/a | n/a |
| `blake2b` | **43.517** | 64.866 | 69.177 | n/a | n/a |
| `sha512` | **47.084** | 50.676 | 49.597 | n/a | n/a |
| `x25519` | **46.592** | 48.623 | 49.256 | n/a | n/a |

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
| _(floor: empty program)_ | _4.296_ | _114.984_ | _**119.280**_ | _63.231_ | _81.968_ | _56.784_ |
| `lcg` | 4.516 | 125.978 | **130.494** | 63.770 | 91.138 | 59.167 |
| `packet_classifier` | 4.695 | 125.476 | **130.171** | 63.028 | 92.120 | 58.719 |
| `ring_write` | 13.895 | 129.329 | **143.224** | 72.300 | 93.481 | 60.219 |
| `histogram_bins` | 13.793 | 128.592 | **142.385** | 72.498 | 111.311 | 67.201 |
| `prefix_scan` | 14.076 | 130.229 | **144.305** | 72.335 | 97.804 | 63.459 |
| `binary_search` | 14.083 | 126.552 | **140.635** | 71.458 | 93.555 | 65.506 |
| `sort_window` | 14.489 | 129.892 | **144.381** | 73.514 | 101.571 | 69.153 |
| `bloom_filter` | 14.840 | 133.056 | **147.896** | 74.191 | 105.616 | 67.581 |
| `hash_join` | 18.367 | 271.338 | **289.705** | 77.749 | 219.111 | 108.899 |
| `sieve` | 13.964 | 124.701 | **138.665** | 70.805 | 102.444 | 68.926 |
| `fib` | 4.603 | 123.375 | **127.978** | 61.952 | 90.921 | 58.482 |
| `collatz` | 4.671 | 124.308 | **128.979** | 61.427 | 93.105 | 58.972 |
| `matmul` | 15.525 | 128.527 | **144.052** | 72.477 | 106.332 | 78.432 |
| `json_parse` | 48.176 | 494.283 | **542.459** | 107.047 | 160.298 | 155.979 |
| `nbody` | 16.544 | 136.640 | **153.184** | 73.432 | 127.658 | 94.169 |
| `chacha20` | 49.120 | 810.466 | **859.586** | 105.819 | 139.123 | 104.201 |
| `poly1305` | 32.559 | 279.162 | **311.721** | 88.876 | 139.817 | 119.410 |
| `blake2b` | 36.865 | 378.014 | **414.879** | 92.736 | 147.421 | 114.628 |
| `sha512` | 37.544 | 480.893 | **518.437** | 94.993 | 139.027 | 101.033 |
| `x25519` | 37.596 | 942.950 | **980.546** | 94.927 | 1228.634 | 495.190 |

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
