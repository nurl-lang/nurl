# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T02:15:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `9fd58c67f4c7ca426db823fc2baeac011c792d6c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40804635429 |
| NURL | `v0.80.0-25-g9fd58c67` |
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
| _(floor: empty program)_ | _1.540_ | _1.503_ | _1.729_ | _24.635_ | _17.678_ |
| `lcg` | 39.193 | **39.158** | 39.477 | 1826.318 | 5086.938 |
| `packet_classifier` | 56.406 | **56.382** | 56.611 | 164.893 | 4393.547 |
| `ring_write` | 42.291 | **42.268** | 42.494 | 66.616 | 6431.620 |
| `histogram_bins` | **39.623** | 40.593 | 40.839 | 67.391 | 5932.626 |
| `prefix_scan` | 21.800 | **21.732** | 21.995 | 66.920 | 4452.872 |
| `binary_search` | 39.776 | **38.344** | 41.004 | 108.578 | 6257.898 |
| `sort_window` | 26.632 | **26.620** | 26.825 | 198.477 | 11931.933 |
| `bloom_filter` | **16.691** | 17.876 | 18.385 | 2861.948 | 7764.475 |
| `hash_join` | **27.091** | 28.105 | 29.368 | 3463.136 | 8325.592 |
| `sieve` | 24.595 | 22.048 | **21.753** | 70.331 | 3219.865 |
| `fib` | **25.128** | 29.896 | 30.196 | 133.423 | 1363.131 |
| `collatz` | 12.278 | **12.218** | 12.535 | 51.468 | 741.079 |
| `matmul` | **33.711** | 33.802 | 34.028 | 80.578 | 3168.629 |
| `json_parse` | **8.471** | 8.728 | 11.885 | 37.703 | 39.652 |
| `nbody` | **25.307** | 39.828 | 25.388 | 102.082 | 3135.890 |
| `chacha20` | **7.310** | 42.103 | 33.857 | n/a | n/a |
| `poly1305` | **11.767** | 31.963 | 21.293 | n/a | n/a |
| `blake2b` | **44.270** | 65.356 | 69.443 | n/a | n/a |
| `sha512` | **47.653** | 50.895 | 49.749 | n/a | n/a |
| `x25519` | **31.917** | 49.488 | 49.761 | n/a | n/a |

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
| _(floor: empty program)_ | _4.765_ | _123.876_ | _**128.641**_ | _64.598_ | _85.313_ | _63.244_ |
| `lcg` | 4.953 | 132.632 | **137.585** | 65.272 | 94.713 | 70.780 |
| `packet_classifier` | 5.108 | 134.223 | **139.331** | 65.356 | 97.318 | 73.311 |
| `ring_write` | 15.742 | 136.625 | **152.367** | 76.129 | 97.664 | 75.432 |
| `histogram_bins` | 15.406 | 135.279 | **150.685** | 74.526 | 114.254 | 82.121 |
| `prefix_scan` | 15.835 | 134.859 | **150.694** | 75.243 | 100.299 | 77.016 |
| `binary_search` | 15.781 | 135.231 | **151.012** | 74.658 | 96.836 | 78.673 |
| `sort_window` | 15.824 | 135.491 | **151.315** | 73.775 | 106.559 | 83.803 |
| `bloom_filter` | 16.551 | 139.085 | **155.636** | 75.719 | 105.703 | 88.113 |
| `hash_join` | 20.303 | 266.135 | **286.438** | 78.495 | 221.941 | 125.328 |
| `sieve` | 15.935 | 133.229 | **149.164** | 75.005 | 106.963 | 86.152 |
| `fib` | 4.935 | 131.803 | **136.738** | 65.727 | 95.613 | 73.772 |
| `collatz` | 5.352 | 137.409 | **142.761** | 67.216 | 98.250 | 77.156 |
| `matmul` | 17.338 | 137.671 | **155.009** | 79.131 | 112.454 | 96.658 |
| `json_parse` | 51.350 | 479.836 | **531.186** | 113.172 | 167.280 | 176.174 |
| `nbody` | 18.518 | 141.539 | **160.057** | 77.982 | 134.476 | 111.468 |
| `chacha20` | 58.158 | 763.668 | **821.826** | 118.436 | 147.207 | 124.376 |
| `poly1305` | 44.449 | 522.962 | **567.411** | 107.153 | 148.830 | 138.686 |
| `blake2b` | 40.071 | 380.755 | **420.826** | 102.212 | 156.237 | 135.129 |
| `sha512` | 40.359 | 484.157 | **524.516** | 101.481 | 147.856 | 118.819 |
| `x25519` | 54.760 | 1317.848 | **1372.608** | 116.211 | 1246.129 | 521.439 |

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
