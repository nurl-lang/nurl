# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-24T06:22:37Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16372432 KiB |
| Commit | `a1d3896365bd24e21e119cec76c586aeaeb4601a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40069569385 |
| NURL | `v0.77.2-32-ga1d38963` |
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
| _(floor: empty program)_ | _1.197_ | _1.188_ | _1.311_ | _22.898_ | _15.032_ |
| `lcg` | **37.259** | 37.351 | 37.517 | 1792.264 | 5203.737 |
| `packet_classifier` | **52.731** | 52.884 | 52.787 | 156.207 | 4167.050 |
| `ring_write` | 40.729 | **40.634** | 41.062 | 71.952 | 6236.855 |
| `histogram_bins` | **39.766** | 40.610 | 41.106 | 70.154 | 6049.642 |
| `prefix_scan` | 21.437 | 21.584 | **20.909** | 68.426 | 4349.713 |
| `binary_search` | 30.099 | **30.089** | 36.610 | 105.923 | 6538.362 |
| `sort_window` | 36.608 | **35.210** | 36.034 | 182.200 | 11231.853 |
| `bloom_filter` | 13.879 | 14.018 | **13.655** | 2755.667 | 7643.137 |
| `hash_join` | **24.735** | 25.195 | 26.797 | 3371.616 | 8046.395 |
| `sieve` | **35.768** | 35.805 | 36.065 | 84.729 | 3535.904 |
| `fib` | 26.612 | **26.292** | 26.577 | 124.458 | 1175.501 |
| `collatz` | 12.791 | **12.453** | 12.605 | 56.648 | 688.368 |
| `matmul` | 16.896 | **16.893** | 17.116 | 72.119 | 3098.046 |
| `json_parse` | **7.021** | 7.357 | 9.674 | 32.676 | 35.314 |
| `nbody` | 22.100 | 35.171 | **21.838** | 92.832 | 2408.280 |
| `chacha20` | **7.454** | 37.986 | 33.327 | n/a | n/a |
| `poly1305` | **12.111** | 34.034 | 25.445 | n/a | n/a |
| `blake2b` | **44.786** | 58.321 | 64.256 | n/a | n/a |
| `sha512` | **45.241** | 47.450 | 48.952 | n/a | n/a |
| `x25519` | **45.029** | 48.178 | 49.310 | n/a | n/a |

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
| _(floor: empty program)_ | _3.607_ | _95.788_ | _**99.395**_ | _53.038_ | _66.487_ | _53.680_ |
| `lcg` | 3.842 | 106.703 | **110.545** | 52.776 | 74.600 | 53.752 |
| `packet_classifier` | 4.042 | 110.465 | **114.507** | 54.778 | 80.516 | 55.799 |
| `ring_write` | 12.808 | 113.421 | **126.229** | 64.655 | 80.256 | 57.398 |
| `histogram_bins` | 13.049 | 117.609 | **130.658** | 66.950 | 99.382 | 66.196 |
| `prefix_scan` | 13.184 | 116.408 | **129.592** | 65.837 | 87.743 | 61.895 |
| `binary_search` | 13.206 | 116.213 | **129.419** | 65.807 | 84.020 | 63.812 |
| `sort_window` | 13.808 | 120.533 | **134.341** | 68.242 | 93.151 | 69.144 |
| `bloom_filter` | 14.090 | 118.946 | **133.036** | 66.302 | 90.649 | 63.262 |
| `hash_join` | 16.944 | 238.507 | **255.451** | 67.777 | 191.778 | 104.589 |
| `sieve` | 13.125 | 113.601 | **126.726** | 63.866 | 88.967 | 67.317 |
| `fib` | 4.280 | 110.122 | **114.402** | 55.444 | 78.888 | 55.215 |
| `collatz` | 4.181 | 112.962 | **117.143** | 55.546 | 78.653 | 54.643 |
| `matmul` | 14.280 | 112.643 | **126.923** | 65.367 | 91.028 | 73.990 |
| `json_parse` | 44.106 | 440.116 | **484.222** | 97.421 | 139.047 | 151.009 |
| `nbody` | 15.592 | 121.000 | **136.592** | 66.033 | 112.073 | 89.648 |
| `chacha20` | 50.239 | 766.444 | **816.683** | 101.366 | 125.877 | 101.366 |
| `poly1305` | 38.277 | 486.632 | **524.909** | 89.161 | 127.052 | 114.706 |
| `blake2b` | 33.853 | 353.770 | **387.623** | 84.854 | 131.197 | 110.688 |
| `sha512` | 33.861 | 429.606 | **463.467** | 85.231 | 120.581 | 96.474 |
| `x25519` | 33.140 | 932.922 | **966.062** | 83.925 | 1194.284 | 479.499 |

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
