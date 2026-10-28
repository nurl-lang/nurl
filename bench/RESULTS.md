# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T06:24:13Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `a5ed413d51b19d68cc6ed105ec77e1254e5c4f26` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40643064599 |
| NURL | `v0.79.1-19-ga5ed413d` |
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
| _(floor: empty program)_ | _1.331_ | _1.412_ | _1.571_ | _22.978_ | _16.412_ |
| `lcg` | **34.542** | 34.596 | 35.369 | 1424.206 | 4164.203 |
| `packet_classifier` | **49.570** | 49.731 | 49.857 | 127.578 | 3564.983 |
| `ring_write` | **37.216** | 37.239 | 37.515 | 62.770 | 4969.015 |
| `histogram_bins` | 35.365 | **35.039** | 35.067 | 61.317 | 4881.541 |
| `prefix_scan` | 19.290 | **19.219** | 19.835 | 61.462 | 3605.901 |
| `binary_search` | 28.551 | **27.954** | 34.112 | 91.644 | 4992.113 |
| `sort_window` | 23.801 | 23.906 | **23.800** | 146.746 | 8941.780 |
| `bloom_filter` | **14.066** | 14.825 | 16.400 | 2202.347 | 6132.917 |
| `hash_join` | **21.894** | 22.565 | 23.846 | 2666.738 | 6459.735 |
| `sieve` | **16.697** | 16.812 | 17.297 | 61.282 | 2799.178 |
| `fib` | **26.086** | 26.127 | 26.513 | 115.199 | 1000.906 |
| `collatz` | 10.971 | **10.855** | 11.239 | 43.248 | 592.155 |
| `matmul` | **36.528** | 36.636 | 37.007 | 73.810 | 2760.521 |
| `json_parse` | **6.947** | 7.657 | 10.546 | 36.245 | 34.803 |
| `nbody` | **21.347** | 35.375 | 21.429 | 80.595 | 2596.471 |
| `chacha20` | **7.016** | 36.087 | 28.045 | n/a | n/a |
| `poly1305` | **10.144** | 31.955 | 19.146 | n/a | n/a |
| `blake2b` | **38.118** | 56.307 | 61.297 | n/a | n/a |
| `sha512` | **39.269** | 40.724 | 43.119 | n/a | n/a |
| `x25519` | **38.455** | 42.268 | 43.829 | n/a | n/a |

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
| _(floor: empty program)_ | _4.905_ | _115.764_ | _**120.669**_ | _60.990_ | _77.904_ | _52.936_ |
| `lcg` | 4.387 | 115.910 | **120.297** | 59.355 | 90.029 | 61.007 |
| `packet_classifier` | 4.965 | 131.252 | **136.217** | 69.024 | 95.796 | 57.306 |
| `ring_write` | 13.858 | 121.001 | **134.859** | 70.330 | 91.665 | 64.292 |
| `histogram_bins` | 14.390 | 128.598 | **142.988** | 73.683 | 107.408 | 74.304 |
| `prefix_scan` | 14.053 | 122.660 | **136.713** | 72.380 | 98.641 | 64.550 |
| `binary_search` | 14.652 | 127.175 | **141.827** | 73.160 | 92.583 | 65.308 |
| `sort_window` | 14.265 | 129.127 | **143.392** | 71.970 | 101.015 | 67.042 |
| `bloom_filter` | 14.886 | 126.990 | **141.876** | 69.081 | 103.639 | 62.896 |
| `hash_join` | 17.944 | 225.691 | **243.635** | 75.964 | 185.602 | 99.721 |
| `sieve` | 14.201 | 126.320 | **140.521** | 71.566 | 98.317 | 71.705 |
| `fib` | 4.860 | 121.578 | **126.438** | 64.464 | 91.105 | 58.135 |
| `collatz` | 4.686 | 118.205 | **122.891** | 61.087 | 87.513 | 55.116 |
| `matmul` | 15.192 | 127.395 | **142.587** | 72.755 | 101.962 | 79.068 |
| `json_parse` | 44.805 | 410.543 | **455.348** | 103.777 | 145.976 | 147.480 |
| `nbody` | 15.953 | 130.265 | **146.218** | 72.312 | 119.943 | 89.807 |
| `chacha20` | 50.659 | 656.881 | **707.540** | 108.700 | 128.373 | 96.880 |
| `poly1305` | 37.869 | 428.508 | **466.377** | 98.083 | 131.879 | 109.585 |
| `blake2b` | 35.649 | 338.590 | **374.239** | 94.436 | 133.995 | 111.623 |
| `sha512` | 36.536 | 411.152 | **447.688** | 101.013 | 134.975 | 101.472 |
| `x25519` | 34.654 | 684.995 | **719.649** | 95.229 | 1012.189 | 425.501 |

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
