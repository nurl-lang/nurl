# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-21T04:58:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `3d2a8a9e3294d4e87f876f34920c0a45bcf0aa1c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39546523968 |
| NURL | `v0.76.0-4-g3d2a8a9e` |
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
| _(floor: empty program)_ | _1.288_ | _1.275_ | _1.437_ | _19.313_ | _12.474_ |
| `lcg` | **29.950** | 29.996 | 30.129 | 1130.540 | 3056.620 |
| `packet_classifier` | 43.705 | 44.414 | **43.285** | 133.035 | 2755.240 |
| `ring_write` | **29.697** | 29.817 | 30.521 | 51.583 | 3662.759 |
| `histogram_bins` | **29.803** | 29.930 | 30.168 | 53.072 | 3489.662 |
| `prefix_scan` | **16.492** | 16.541 | 16.790 | 50.074 | 2579.587 |
| `binary_search` | 15.176 | **14.846** | 16.062 | 72.956 | 3684.715 |
| `sort_window` | 20.835 | **20.611** | 20.737 | 137.531 | 6712.563 |
| `bloom_filter` | **8.986** | 9.049 | 9.174 | 1651.838 | 4517.384 |
| `hash_join` | **16.305** | 17.293 | 18.291 | 1973.756 | 4596.136 |
| `sieve` | 15.846 | **14.657** | 14.975 | 47.616 | 1843.593 |
| `fib` | 19.829 | 19.466 | **19.334** | 79.475 | 685.621 |
| `collatz` | **9.427** | 9.657 | 9.530 | 38.306 | 416.678 |
| `matmul` | 21.233 | 21.441 | **21.080** | 54.886 | 1832.159 |
| `json_parse` | **5.279** | 5.597 | 7.109 | 25.120 | 25.904 |
| `nbody` | **17.810** | 26.115 | 18.234 | 63.817 | 1546.378 |
| `chacha20` | **6.869** | 20.041 | 19.527 | n/a | n/a |
| `poly1305` | **15.645** | 26.999 | 15.673 | n/a | n/a |
| `blake2b` | **26.687** | 42.707 | 49.604 | n/a | n/a |
| `sha512` | **31.308** | 33.744 | 33.196 | n/a | n/a |
| `x25519` | **28.856** | 30.945 | 32.604 | n/a | n/a |

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
| _(floor: empty program)_ | _3.638_ | _92.054_ | _**95.692**_ | _55.146_ | _74.060_ | _54.568_ |
| `lcg` | 3.535 | 97.743 | **101.278** | 54.305 | 81.955 | 62.878 |
| `packet_classifier` | 3.772 | 96.979 | **100.751** | 52.407 | 84.289 | 63.331 |
| `ring_write` | 9.317 | 96.810 | **106.127** | 57.201 | 91.144 | 61.267 |
| `histogram_bins` | 9.485 | 99.201 | **108.686** | 57.695 | 88.317 | 66.310 |
| `prefix_scan` | 9.555 | 104.738 | **114.293** | 59.367 | 79.680 | 62.235 |
| `binary_search` | 9.480 | 97.415 | **106.895** | 57.735 | 95.217 | 63.498 |
| `sort_window` | 9.908 | 102.609 | **112.517** | 59.090 | 90.591 | 69.805 |
| `bloom_filter` | 9.857 | 99.403 | **109.260** | 58.926 | 87.878 | 68.018 |
| `hash_join` | 11.854 | 182.342 | **194.196** | 60.615 | 149.229 | 98.163 |
| `sieve` | 9.384 | 97.303 | **106.687** | 57.761 | 89.331 | 70.979 |
| `fib` | 3.775 | 94.217 | **97.992** | 52.656 | 79.135 | 60.184 |
| `collatz` | 3.688 | 95.361 | **99.049** | 51.806 | 79.392 | 61.819 |
| `matmul` | 10.152 | 100.040 | **110.192** | 59.665 | 85.423 | 78.744 |
| `json_parse` | 28.340 | 317.392 | **345.732** | 76.282 | 124.735 | 140.624 |
| `nbody` | 11.300 | 107.812 | **119.112** | 59.429 | 101.501 | 87.635 |
| `chacha20` | 28.212 | 489.792 | **518.004** | 77.499 | 105.323 | 95.568 |
| `poly1305` | 19.318 | 189.635 | **208.953** | 68.167 | 109.322 | 104.233 |
| `blake2b` | 22.143 | 247.987 | **270.130** | 70.362 | 114.183 | 102.115 |
| `sha512` | 23.555 | 314.842 | **338.397** | 73.830 | 133.463 | 94.435 |
| `x25519` | 24.668 | 452.783 | **477.451** | 72.980 | 783.829 | 336.291 |

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
