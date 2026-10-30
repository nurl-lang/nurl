# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T04:54:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9e83818f25b7eda7008d32c1ba1570330ed56142` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41004925898 |
| NURL | `v0.80.0-107-g9e83818f` |
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
| _(floor: empty program)_ | _1.617_ | _1.669_ | _1.817_ | _27.891_ | _20.561_ |
| `lcg` | 39.551 | **39.456** | 39.700 | 1828.121 | 5091.500 |
| `packet_classifier` | 56.652 | **56.641** | 56.776 | 165.519 | 4312.775 |
| `ring_write` | 42.612 | **42.547** | 42.753 | 71.533 | 6439.810 |
| `histogram_bins` | **40.044** | 41.061 | 41.351 | 70.737 | 6136.917 |
| `prefix_scan` | **22.068** | 22.096 | 22.377 | 69.451 | 4481.428 |
| `binary_search` | 40.152 | **38.753** | 41.473 | 112.508 | 6183.433 |
| `sort_window` | 27.036 | **26.963** | 27.329 | 201.316 | 12034.941 |
| `bloom_filter` | **17.048** | 18.356 | 18.902 | 2880.720 | 7450.417 |
| `hash_join` | **27.250** | 28.526 | 29.876 | 3507.957 | 8476.979 |
| `sieve` | 24.114 | **23.372** | 23.467 | 73.380 | 3278.082 |
| `fib` | **26.432** | 30.234 | 30.455 | 133.614 | 1364.007 |
| `collatz` | **12.706** | 12.736 | 13.079 | 54.556 | 754.293 |
| `matmul` | 34.204 | **34.111** | 34.512 | 82.709 | 3253.800 |
| `json_parse` | **8.928** | 9.280 | 12.446 | 40.866 | 42.213 |
| `nbody` | **25.771** | 40.186 | 25.915 | 104.325 | 3105.764 |
| `chacha20` | **7.823** | 42.788 | 34.380 | n/a | n/a |
| `poly1305` | **12.416** | 32.412 | 21.795 | n/a | n/a |
| `blake2b` | **44.676** | 65.585 | 69.868 | n/a | n/a |
| `sha512` | **47.896** | 51.060 | 49.926 | n/a | n/a |
| `x25519` | **32.047** | 49.198 | 49.833 | n/a | n/a |

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
| _(floor: empty program)_ | _5.788_ | _132.604_ | _**138.392**_ | _71.478_ | _92.425_ | _69.229_ |
| `lcg` | 5.334 | 145.819 | **151.153** | 70.811 | 101.780 | 76.363 |
| `packet_classifier` | 5.259 | 142.698 | **147.957** | 70.427 | 105.531 | 79.161 |
| `ring_write` | 16.473 | 144.155 | **160.628** | 80.309 | 105.645 | 80.526 |
| `histogram_bins` | 16.490 | 146.659 | **163.149** | 80.057 | 123.148 | 88.857 |
| `prefix_scan` | 16.675 | 147.198 | **163.873** | 80.179 | 111.457 | 83.358 |
| `binary_search` | 16.931 | 148.777 | **165.708** | 81.556 | 106.827 | 85.434 |
| `sort_window` | 17.102 | 149.797 | **166.899** | 81.529 | 117.535 | 93.486 |
| `bloom_filter` | 17.704 | 151.921 | **169.625** | 81.783 | 117.547 | 87.183 |
| `hash_join` | 21.162 | 280.777 | **301.939** | 84.464 | 233.882 | 134.200 |
| `sieve` | 16.957 | 148.367 | **165.324** | 82.071 | 118.116 | 92.762 |
| `fib` | 5.365 | 143.347 | **148.712** | 71.143 | 104.457 | 79.745 |
| `collatz` | 5.589 | 145.696 | **151.285** | 70.181 | 104.708 | 79.580 |
| `matmul` | 18.264 | 146.352 | **164.616** | 82.744 | 121.109 | 105.227 |
| `json_parse` | 54.771 | 508.800 | **563.571** | 121.398 | 177.993 | 197.506 |
| `nbody` | 19.211 | 151.963 | **171.174** | 84.472 | 153.589 | 121.254 |
| `chacha20` | 62.753 | 803.834 | **866.587** | 128.889 | 159.479 | 137.354 |
| `poly1305` | 48.276 | 554.106 | **602.382** | 115.799 | 160.566 | 155.923 |
| `blake2b` | 43.244 | 406.576 | **449.820** | 111.568 | 164.659 | 148.728 |
| `sha512` | 42.547 | 506.502 | **549.049** | 107.635 | 155.567 | 128.378 |
| `x25519` | 58.021 | 1343.639 | **1401.660** | 124.090 | 1279.495 | 541.418 |

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
