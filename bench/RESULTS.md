# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T02:26:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `5f1d332aec80f3cc7bea6ca4c7d012a905f60dad` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40991051715 |
| NURL | `v0.80.0-95-g5f1d332a` |
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
| _(floor: empty program)_ | _1.547_ | _1.501_ | _1.748_ | _24.359_ | _18.169_ |
| `lcg` | **39.342** | 39.367 | 39.656 | 1829.845 | 5011.409 |
| `packet_classifier` | 56.559 | **56.407** | 56.663 | 163.419 | 4355.574 |
| `ring_write` | **42.395** | 42.528 | 42.658 | 68.744 | 6398.560 |
| `histogram_bins` | **39.626** | 40.713 | 40.987 | 68.620 | 6092.664 |
| `prefix_scan` | 21.812 | **21.734** | 21.961 | 68.227 | 4460.422 |
| `binary_search` | 39.974 | **38.372** | 40.965 | 107.927 | 6097.385 |
| `sort_window` | 26.788 | **26.689** | 26.883 | 198.670 | 11437.185 |
| `bloom_filter` | **16.722** | 18.047 | 18.483 | 2879.862 | 7629.553 |
| `hash_join` | **27.088** | 28.287 | 29.249 | 3500.872 | 8188.364 |
| `sieve` | 23.219 | 22.711 | **22.498** | 70.494 | 3217.475 |
| `fib` | **25.415** | 29.973 | 30.168 | 133.784 | 1359.987 |
| `collatz` | 12.581 | **12.345** | 12.622 | 51.640 | 739.506 |
| `matmul` | 33.880 | **33.681** | 33.977 | 78.807 | 3465.592 |
| `json_parse` | **8.476** | 8.950 | 12.006 | 39.061 | 40.869 |
| `nbody` | **25.360** | 40.005 | 25.389 | 100.738 | 3125.596 |
| `chacha20` | **7.377** | 42.344 | 33.971 | n/a | n/a |
| `poly1305` | **11.816** | 32.022 | 21.284 | n/a | n/a |
| `blake2b` | **44.186** | 65.394 | 69.329 | n/a | n/a |
| `sha512` | **47.654** | 50.769 | 49.916 | n/a | n/a |
| `x25519` | **31.929** | 48.849 | 49.688 | n/a | n/a |

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
| _(floor: empty program)_ | _5.301_ | _121.519_ | _**126.820**_ | _67.935_ | _85.578_ | _65.826_ |
| `lcg` | 4.878 | 134.949 | **139.827** | 66.733 | 95.448 | 74.206 |
| `packet_classifier` | 5.005 | 133.325 | **138.330** | 66.580 | 96.344 | 75.904 |
| `ring_write` | 15.499 | 133.986 | **149.485** | 74.442 | 96.402 | 73.390 |
| `histogram_bins` | 15.831 | 135.376 | **151.207** | 76.472 | 112.168 | 81.294 |
| `prefix_scan` | 15.727 | 134.848 | **150.575** | 76.191 | 102.064 | 75.601 |
| `binary_search` | 15.727 | 131.744 | **147.471** | 73.774 | 97.135 | 79.216 |
| `sort_window` | 15.853 | 134.229 | **150.082** | 73.809 | 106.980 | 82.497 |
| `bloom_filter` | 16.315 | 136.282 | **152.597** | 74.553 | 105.671 | 80.031 |
| `hash_join` | 20.430 | 269.398 | **289.828** | 80.975 | 223.792 | 126.837 |
| `sieve` | 16.009 | 136.549 | **152.558** | 76.449 | 108.752 | 86.611 |
| `fib` | 5.125 | 132.588 | **137.713** | 65.637 | 94.795 | 72.210 |
| `collatz` | 5.125 | 135.244 | **140.369** | 66.218 | 96.993 | 74.114 |
| `matmul` | 17.222 | 135.992 | **153.214** | 76.846 | 113.157 | 95.839 |
| `json_parse` | 51.793 | 481.627 | **533.420** | 113.256 | 166.949 | 182.807 |
| `nbody` | 18.883 | 142.407 | **161.290** | 79.528 | 135.015 | 112.537 |
| `chacha20` | 58.627 | 767.795 | **826.422** | 119.224 | 147.562 | 123.452 |
| `poly1305` | 44.343 | 520.593 | **564.936** | 105.309 | 148.384 | 138.295 |
| `blake2b` | 40.141 | 382.490 | **422.631** | 100.614 | 153.257 | 132.324 |
| `sha512` | 40.090 | 482.892 | **522.982** | 102.083 | 144.840 | 118.988 |
| `x25519` | 54.527 | 1314.234 | **1368.761** | 115.452 | 1232.203 | 515.144 |

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
