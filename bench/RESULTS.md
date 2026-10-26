# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T16:43:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `d09c6c68f897acc082d6d0c81402eba2b9f92be4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40361006628 |
| NURL | `v0.78.0-29-gd09c6c68` |
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
| _(floor: empty program)_ | _1.223_ | _1.198_ | _1.363_ | _19.591_ | _13.735_ |
| `lcg` | 34.284 | **34.220** | 34.334 | 1411.414 | 4117.666 |
| `packet_classifier` | **49.185** | 49.220 | 49.440 | 124.633 | 3551.662 |
| `ring_write` | 36.969 | **36.908** | 37.056 | 57.462 | 4947.798 |
| `histogram_bins` | **34.558** | 34.574 | 34.728 | 58.781 | 4921.693 |
| `prefix_scan` | 18.954 | **18.893** | 19.106 | 56.912 | 3639.028 |
| `binary_search` | 28.057 | **27.675** | 33.516 | 87.562 | 5646.591 |
| `sort_window` | 23.226 | **23.213** | 23.425 | 129.448 | 8832.984 |
| `bloom_filter` | **13.429** | 14.485 | 15.982 | 2134.549 | 6038.774 |
| `hash_join` | **21.394** | 22.146 | 23.338 | 2679.542 | 6500.653 |
| `sieve` | 15.810 | 15.552 | **15.534** | 57.495 | 2677.684 |
| `fib` | 25.638 | **25.631** | 25.790 | 110.826 | 1003.323 |
| `collatz` | 10.615 | **10.578** | 10.805 | 40.454 | 580.305 |
| `matmul` | **35.969** | 35.999 | 36.340 | 65.207 | 2791.855 |
| `json_parse` | **6.159** | 6.876 | 9.381 | 29.812 | 30.681 |
| `nbody` | 20.902 | 34.794 | **20.799** | 74.272 | 2589.167 |
| `chacha20` | **6.689** | 35.612 | 27.609 | n/a | n/a |
| `poly1305` | **9.900** | 31.196 | 18.458 | n/a | n/a |
| `blake2b` | **37.649** | 55.644 | 60.434 | n/a | n/a |
| `sha512` | **38.525** | 40.129 | 42.319 | n/a | n/a |
| `x25519` | **38.020** | 42.113 | 43.291 | n/a | n/a |

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
| _(floor: empty program)_ | _3.981_ | _96.202_ | _**100.183**_ | _54.429_ | _69.882_ | _44.639_ |
| `lcg` | 3.818 | 105.467 | **109.285** | 53.791 | 77.145 | 48.790 |
| `packet_classifier` | 4.009 | 105.711 | **109.720** | 53.897 | 80.639 | 49.171 |
| `ring_write` | 12.552 | 108.032 | **120.584** | 62.755 | 79.333 | 50.669 |
| `histogram_bins` | 12.503 | 109.825 | **122.328** | 63.720 | 92.245 | 56.189 |
| `prefix_scan` | 12.544 | 108.973 | **121.517** | 62.789 | 83.576 | 53.332 |
| `binary_search` | 12.669 | 109.658 | **122.327** | 63.356 | 80.556 | 53.831 |
| `sort_window` | 12.796 | 111.001 | **123.797** | 63.898 | 88.228 | 57.944 |
| `bloom_filter` | 13.194 | 112.317 | **125.511** | 64.679 | 87.302 | 54.708 |
| `hash_join` | 15.801 | 207.505 | **223.306** | 67.075 | 170.848 | 91.309 |
| `sieve` | 12.766 | 109.387 | **122.153** | 64.098 | 87.057 | 58.528 |
| `fib` | 4.123 | 106.281 | **110.404** | 54.627 | 79.496 | 49.594 |
| `collatz` | 4.172 | 107.469 | **111.641** | 54.364 | 79.805 | 50.183 |
| `matmul` | 13.932 | 110.501 | **124.433** | 65.025 | 89.562 | 65.044 |
| `json_parse` | 38.862 | 370.478 | **409.340** | 90.435 | 130.685 | 125.957 |
| `nbody` | 14.735 | 115.162 | **129.897** | 65.777 | 105.613 | 78.125 |
| `chacha20` | 43.616 | 620.986 | **664.602** | 94.386 | 116.762 | 86.054 |
| `poly1305` | 33.476 | 395.746 | **429.222** | 84.424 | 116.379 | 97.887 |
| `blake2b` | 30.730 | 296.589 | **327.319** | 81.155 | 119.384 | 93.960 |
| `sha512` | 30.589 | 360.208 | **390.797** | 81.392 | 113.996 | 83.189 |
| `x25519` | 30.419 | 627.886 | **658.305** | 81.128 | 934.147 | 386.777 |

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
