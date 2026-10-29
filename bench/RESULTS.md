# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T09:20:56Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | INTEL(R) XEON(R) PLATINUM 8573C (4 logical cores) |
| Memory | 16366512 KiB |
| Commit | `ca90ea191966872636ef5ef5a3095764e01aaa03` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40848154566 |
| NURL | `v0.80.0-49-gca90ea19` |
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
| _(floor: empty program)_ | _1.331_ | _1.308_ | _1.465_ | _24.966_ | _16.515_ |
| `lcg` | **41.876** | 41.917 | 42.184 | 1556.621 | 4290.043 |
| `packet_classifier` | **71.603** | 72.766 | 72.562 | 174.136 | 3512.238 |
| `ring_write` | 45.985 | **45.444** | 46.467 | 69.895 | 5157.988 |
| `histogram_bins` | 42.919 | **42.877** | 43.087 | 71.730 | 4897.804 |
| `prefix_scan` | 23.244 | **23.043** | 23.409 | 69.937 | 3676.224 |
| `binary_search` | 40.700 | **32.912** | 42.551 | 115.367 | 5456.810 |
| `sort_window` | 41.301 | **41.255** | 42.037 | 188.287 | 9286.724 |
| `bloom_filter` | **14.656** | 14.834 | 15.017 | 2502.238 | 7050.652 |
| `hash_join` | **24.770** | 26.097 | 26.658 | 3128.730 | 7321.422 |
| `sieve` | 40.909 | **40.347** | 41.229 | 90.881 | 3002.296 |
| `fib` | **28.640** | 31.350 | 30.536 | 118.003 | 931.516 |
| `collatz` | **15.646** | 15.862 | 16.471 | 62.111 | 593.461 |
| `matmul` | **21.164** | 21.306 | 21.208 | 77.234 | 2735.218 |
| `json_parse` | **7.110** | 7.820 | 10.012 | 33.661 | 35.108 |
| `nbody` | **23.102** | 32.774 | 23.351 | 82.511 | 2185.764 |
| `chacha20` | **8.408** | 38.383 | 32.982 | n/a | n/a |
| `poly1305` | **13.587** | 35.729 | 23.852 | n/a | n/a |
| `blake2b` | **44.575** | 50.857 | 54.636 | n/a | n/a |
| `sha512` | **43.858** | 45.506 | 46.970 | n/a | n/a |
| `x25519` | **29.972** | 44.141 | 43.341 | n/a | n/a |

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
| _(floor: empty program)_ | _4.600_ | _112.457_ | _**117.057**_ | _59.732_ | _73.682_ | _57.780_ |
| `lcg` | 4.472 | 116.665 | **121.137** | 57.333 | 79.533 | 70.189 |
| `packet_classifier` | 4.624 | 117.266 | **121.890** | 57.763 | 82.127 | 65.028 |
| `ring_write` | 15.617 | 119.854 | **135.471** | 67.438 | 83.078 | 67.595 |
| `histogram_bins` | 15.561 | 120.723 | **136.284** | 67.378 | 100.332 | 75.081 |
| `prefix_scan` | 15.689 | 120.170 | **135.859** | 67.975 | 87.426 | 70.200 |
| `binary_search` | 16.022 | 119.809 | **135.831** | 68.348 | 82.605 | 71.571 |
| `sort_window` | 16.100 | 122.158 | **138.258** | 68.156 | 91.631 | 77.826 |
| `bloom_filter` | 16.600 | 123.680 | **140.280** | 68.708 | 91.104 | 73.342 |
| `hash_join` | 19.688 | 236.015 | **255.703** | 72.569 | 192.039 | 120.333 |
| `sieve` | 15.828 | 118.572 | **134.400** | 68.327 | 92.339 | 79.509 |
| `fib` | 4.847 | 117.658 | **122.505** | 59.226 | 81.294 | 66.711 |
| `collatz` | 4.933 | 119.104 | **124.037** | 57.498 | 82.405 | 66.708 |
| `matmul` | 17.296 | 122.424 | **139.720** | 69.229 | 94.134 | 87.963 |
| `json_parse` | 50.130 | 430.781 | **480.911** | 104.383 | 144.669 | 177.022 |
| `nbody` | 18.329 | 125.322 | **143.651** | 70.592 | 114.143 | 105.045 |
| `chacha20` | 54.123 | 701.836 | **755.959** | 108.545 | 128.224 | 116.808 |
| `poly1305` | 42.075 | 476.722 | **518.797** | 96.435 | 128.800 | 131.210 |
| `blake2b` | 38.331 | 349.935 | **388.266** | 91.421 | 132.812 | 127.750 |
| `sha512` | 38.669 | 431.867 | **470.536** | 92.051 | 125.934 | 113.649 |
| `x25519` | 50.597 | 1245.631 | **1296.228** | 104.843 | 1210.414 | 513.913 |

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
