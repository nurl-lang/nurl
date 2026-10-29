# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T21:53:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `65fffc0861cf664fd845ec36bcbd397e359b53ae` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40960687928 |
| NURL | `v0.80.0-81-g65fffc08` |
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
| _(floor: empty program)_ | _1.536_ | _1.516_ | _1.725_ | _25.389_ | _17.585_ |
| `lcg` | 39.347 | **39.190** | 39.419 | 1826.129 | 5101.795 |
| `packet_classifier` | **56.232** | 56.431 | 56.617 | 164.312 | 4628.579 |
| `ring_write` | 42.365 | **42.351** | 42.523 | 66.560 | 6443.592 |
| `histogram_bins` | **39.617** | 40.696 | 40.960 | 67.421 | 6168.779 |
| `prefix_scan` | **21.780** | 21.816 | 22.029 | 67.701 | 4692.330 |
| `binary_search` | 39.830 | **38.504** | 41.465 | 107.794 | 6133.792 |
| `sort_window` | **26.839** | 26.869 | 27.175 | 199.370 | 11708.614 |
| `bloom_filter` | **16.782** | 18.000 | 18.578 | 2856.067 | 7573.905 |
| `hash_join` | **26.960** | 28.103 | 29.471 | 3462.885 | 8779.682 |
| `sieve` | 24.771 | 24.019 | **23.071** | 71.898 | 3345.337 |
| `fib` | **25.361** | 30.027 | 30.457 | 133.315 | 1365.612 |
| `collatz` | 12.392 | **12.215** | 12.524 | 51.545 | 744.744 |
| `matmul` | 33.743 | **33.713** | 34.096 | 78.019 | 3324.609 |
| `json_parse` | **8.502** | 8.702 | 11.883 | 36.859 | 39.586 |
| `nbody` | **25.234** | 39.971 | 25.387 | 102.068 | 3158.297 |
| `chacha20` | **7.416** | 40.580 | 33.996 | n/a | n/a |
| `poly1305` | **11.844** | 32.043 | 21.433 | n/a | n/a |
| `blake2b` | **44.040** | 66.256 | 69.187 | n/a | n/a |
| `sha512` | **47.892** | 50.844 | 49.802 | n/a | n/a |
| `x25519` | **31.704** | 48.767 | 49.661 | n/a | n/a |

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
| _(floor: empty program)_ | _4.987_ | _122.918_ | _**127.905**_ | _66.896_ | _85.954_ | _62.134_ |
| `lcg` | 4.800 | 130.131 | **134.931** | 64.015 | 93.515 | 73.413 |
| `packet_classifier` | 5.039 | 133.842 | **138.881** | 66.041 | 95.890 | 74.492 |
| `ring_write` | 15.672 | 132.164 | **147.836** | 73.649 | 95.422 | 73.103 |
| `histogram_bins` | 15.613 | 133.209 | **148.822** | 74.652 | 111.719 | 79.686 |
| `prefix_scan` | 15.687 | 133.042 | **148.729** | 74.336 | 101.576 | 75.575 |
| `binary_search` | 15.788 | 134.640 | **150.428** | 75.093 | 95.871 | 77.314 |
| `sort_window` | 16.089 | 134.629 | **150.718** | 73.962 | 106.163 | 83.198 |
| `bloom_filter` | 16.494 | 136.942 | **153.436** | 75.466 | 105.970 | 79.721 |
| `hash_join` | 20.232 | 268.847 | **289.079** | 80.210 | 222.931 | 125.516 |
| `sieve` | 16.075 | 136.909 | **152.984** | 74.477 | 108.814 | 85.675 |
| `fib` | 4.979 | 132.720 | **137.699** | 66.426 | 95.680 | 73.900 |
| `collatz` | 5.344 | 138.462 | **143.806** | 67.129 | 96.104 | 72.879 |
| `matmul` | 17.306 | 135.171 | **152.477** | 76.229 | 110.570 | 95.667 |
| `json_parse` | 51.785 | 488.307 | **540.092** | 112.799 | 166.698 | 177.753 |
| `nbody` | 18.599 | 141.360 | **159.959** | 77.859 | 133.695 | 111.282 |
| `chacha20` | 58.841 | 764.401 | **823.242** | 119.616 | 145.958 | 121.648 |
| `poly1305` | 44.639 | 519.586 | **564.225** | 104.168 | 147.768 | 136.232 |
| `blake2b` | 39.487 | 379.481 | **418.968** | 99.643 | 152.694 | 132.794 |
| `sha512` | 40.002 | 481.132 | **521.134** | 99.753 | 144.658 | 118.058 |
| `x25519` | 55.135 | 1313.389 | **1368.524** | 116.444 | 1233.857 | 521.134 |

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
