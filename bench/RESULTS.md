# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T20:44:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `f1446bbdc2e030c4168289825b48f91aaf579c95` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40579835335 |
| NURL | `v0.79.0-10-gf1446bbd` |
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
| _(floor: empty program)_ | _1.438_ | _1.443_ | _1.608_ | _20.771_ | _17.000_ |
| `lcg` | 39.208 | **39.020** | 39.270 | 1898.961 | 5084.863 |
| `packet_classifier` | **56.059** | 56.220 | 56.385 | 160.943 | 4532.280 |
| `ring_write` | 42.222 | **42.204** | 42.325 | 64.732 | 6383.706 |
| `histogram_bins` | **40.637** | 40.817 | 40.799 | 67.355 | 6026.333 |
| `prefix_scan` | 21.624 | **21.592** | 21.800 | 64.790 | 4546.002 |
| `binary_search` | **38.181** | 38.296 | 40.838 | 106.504 | 6009.422 |
| `sort_window` | 26.649 | **26.555** | 26.713 | 199.457 | 11398.759 |
| `bloom_filter` | **15.364** | 17.806 | 18.298 | 2847.613 | 7737.267 |
| `hash_join` | **26.962** | 27.890 | 29.178 | 3403.932 | 8511.799 |
| `sieve` | 18.141 | **17.712** | 17.991 | 64.181 | 3322.968 |
| `fib` | **29.781** | 29.860 | 29.977 | 131.964 | 1370.001 |
| `collatz` | 12.290 | **12.109** | 12.372 | 48.004 | 742.197 |
| `matmul` | **33.355** | 33.426 | 33.704 | 75.172 | 3352.217 |
| `json_parse` | **8.011** | 8.490 | 11.663 | 35.666 | 38.076 |
| `nbody` | **25.154** | 39.688 | 25.226 | 100.840 | 3173.894 |
| `chacha20` | **7.251** | 42.098 | 33.684 | n/a | n/a |
| `poly1305` | **11.913** | 31.982 | 21.069 | n/a | n/a |
| `blake2b` | **43.565** | 64.954 | 69.386 | n/a | n/a |
| `sha512` | **46.997** | 50.537 | 49.347 | n/a | n/a |
| `x25519` | **44.395** | 48.519 | 49.298 | n/a | n/a |

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
| _(floor: empty program)_ | _4.352_ | _112.584_ | _**116.936**_ | _60.666_ | _79.100_ | _52.800_ |
| `lcg` | 4.504 | 126.166 | **130.670** | 60.798 | 87.749 | 57.104 |
| `packet_classifier` | 4.569 | 125.526 | **130.095** | 61.431 | 89.111 | 58.220 |
| `ring_write` | 15.081 | 128.513 | **143.594** | 72.592 | 90.499 | 59.803 |
| `histogram_bins` | 14.897 | 130.174 | **145.071** | 72.449 | 107.561 | 66.105 |
| `prefix_scan` | 15.219 | 132.666 | **147.885** | 74.250 | 98.483 | 63.411 |
| `binary_search` | 15.302 | 131.703 | **147.005** | 71.783 | 92.306 | 64.124 |
| `sort_window` | 15.615 | 132.045 | **147.660** | 72.971 | 103.459 | 68.512 |
| `bloom_filter` | 16.078 | 133.907 | **149.985** | 73.130 | 103.948 | 65.850 |
| `hash_join` | 19.452 | 267.051 | **286.503** | 76.386 | 221.300 | 109.739 |
| `sieve` | 15.522 | 129.121 | **144.643** | 72.358 | 102.497 | 69.341 |
| `fib` | 4.717 | 129.719 | **134.436** | 63.349 | 91.451 | 58.919 |
| `collatz` | 4.861 | 128.882 | **133.743** | 61.652 | 90.507 | 59.085 |
| `matmul` | 16.731 | 130.230 | **146.961** | 74.074 | 105.913 | 78.541 |
| `json_parse` | 49.758 | 492.462 | **542.220** | 107.280 | 161.245 | 155.313 |
| `nbody` | 17.813 | 138.005 | **155.818** | 75.383 | 126.661 | 94.251 |
| `chacha20` | 57.003 | 763.384 | **820.387** | 115.297 | 142.887 | 105.261 |
| `poly1305` | 43.253 | 516.817 | **560.070** | 101.804 | 143.226 | 119.999 |
| `blake2b` | 38.529 | 383.534 | **422.063** | 96.980 | 149.692 | 114.342 |
| `sha512` | 38.732 | 479.283 | **518.015** | 97.031 | 138.774 | 100.032 |
| `x25519` | 40.085 | 833.473 | **873.558** | 99.231 | 1224.435 | 491.460 |

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
