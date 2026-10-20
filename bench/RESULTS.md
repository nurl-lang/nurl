# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-20T14:45:30Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367516 KiB |
| Commit | `7a6740f7bcf6f2c1a19551dbea061ae42fa0b5fc` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39441472086 |
| NURL | `v0.75.0-3-g7a6740f7` |
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
| _(floor: empty program)_ | _1.252_ | _1.205_ | _1.367_ | _17.448_ | _12.035_ |
| `lcg` | 33.994 | 29.505 | **29.433** | 1136.012 | 3104.850 |
| `packet_classifier` | **42.328** | 42.374 | 42.358 | 130.786 | 2739.588 |
| `ring_write` | 29.844 | **29.787** | 29.799 | 49.726 | 3693.298 |
| `histogram_bins` | 30.301 | **30.247** | 30.340 | 49.888 | 3427.164 |
| `prefix_scan` | 16.352 | **16.268** | 16.347 | 49.126 | 2520.463 |
| `binary_search` | 14.803 | **14.617** | 15.594 | 68.249 | 3597.031 |
| `sort_window` | 20.542 | **20.279** | 20.597 | 138.155 | 6164.065 |
| `bloom_filter` | 8.964 | 8.946 | **8.885** | 1685.448 | 4390.739 |
| `hash_join` | **16.466** | 17.199 | 18.327 | 1989.877 | 4659.797 |
| `sieve` | 15.483 | **14.793** | 15.230 | 48.111 | 1908.894 |
| `fib` | 19.846 | **19.531** | 19.589 | 77.802 | 698.610 |
| `collatz` | 9.507 | **9.422** | 9.649 | 36.326 | 417.695 |
| `matmul` | **20.728** | 21.071 | 20.953 | 54.312 | 1811.630 |
| `json_parse` | **4.961** | 5.461 | 6.951 | 24.683 | 24.213 |
| `nbody` | **16.933** | 25.007 | 20.099 | 59.708 | 1471.806 |
| `chacha20` | **6.928** | 20.022 | 19.588 | n/a | n/a |
| `poly1305` | **15.249** | 27.148 | 15.882 | n/a | n/a |
| `blake2b` | **26.752** | 43.439 | 47.920 | n/a | n/a |
| `sha512` | **30.076** | 32.844 | 32.278 | n/a | n/a |
| `x25519` | **27.555** | 30.232 | 30.494 | n/a | n/a |

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
| _(floor: empty program)_ | _3.293_ | _79.654_ | _**82.947**_ | _49.381_ | _65.989_ | _50.925_ |
| `lcg` | 3.520 | 90.238 | **93.758** | 49.757 | 72.297 | 57.022 |
| `packet_classifier` | 3.570 | 93.716 | **97.286** | 51.187 | 80.575 | 60.468 |
| `ring_write` | 9.079 | 93.016 | **102.095** | 55.345 | 93.611 | 60.304 |
| `histogram_bins` | 9.271 | 96.175 | **105.446** | 55.526 | 83.640 | 63.886 |
| `prefix_scan` | 9.301 | 92.069 | **101.370** | 54.996 | 78.791 | 60.904 |
| `binary_search` | 9.367 | 91.758 | **101.125** | 55.976 | 76.318 | 64.745 |
| `sort_window` | 9.430 | 95.660 | **105.090** | 56.371 | 82.491 | 66.700 |
| `bloom_filter` | 9.514 | 93.599 | **103.113** | 55.158 | 81.048 | 63.488 |
| `hash_join` | 11.943 | 181.985 | **193.928** | 60.400 | 150.348 | 101.835 |
| `sieve` | 9.259 | 92.728 | **101.987** | 55.545 | 84.703 | 69.084 |
| `fib` | 3.567 | 90.746 | **94.313** | 49.719 | 74.733 | 59.885 |
| `collatz` | 3.746 | 92.843 | **96.589** | 50.731 | 76.015 | 60.531 |
| `matmul` | 10.185 | 94.756 | **104.941** | 56.825 | 85.360 | 75.568 |
| `json_parse` | 28.150 | 312.263 | **340.413** | 76.647 | 122.286 | 134.522 |
| `nbody` | 10.646 | 104.889 | **115.535** | 57.048 | 97.226 | 84.035 |
| `chacha20` | 27.237 | 482.346 | **509.583** | 74.426 | 103.443 | 95.392 |
| `poly1305` | 19.002 | 190.062 | **209.064** | 66.750 | 107.606 | 102.238 |
| `blake2b` | 23.021 | 252.621 | **275.642** | 71.930 | 112.335 | 102.057 |
| `sha512` | 21.890 | 306.337 | **328.227** | 70.330 | 108.117 | 103.820 |
| `x25519` | 23.696 | 446.949 | **470.645** | 71.193 | 732.336 | 331.331 |

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
