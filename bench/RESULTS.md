# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T04:15:36Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `7c06f35c39289611fed8506d631e5b9f2beb2aac` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40448322708 |
| NURL | `v0.78.0-37-g7c06f35c` |
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
| _(floor: empty program)_ | _1.148_ | _1.093_ | _1.232_ | _17.116_ | _11.340_ |
| `lcg` | 28.272 | **28.232** | 28.426 | 1098.178 | 3037.087 |
| `packet_classifier` | **42.362** | 42.494 | 42.681 | 133.311 | 2735.596 |
| `ring_write` | **29.230** | 29.524 | 29.740 | 51.773 | 3686.831 |
| `histogram_bins` | 29.590 | **29.414** | 29.808 | 51.097 | 3424.289 |
| `prefix_scan` | 15.640 | **15.607** | 15.700 | 47.846 | 2484.195 |
| `binary_search` | 14.069 | **14.053** | 14.968 | 67.778 | 3758.714 |
| `sort_window` | 19.675 | **19.669** | 19.961 | 130.766 | 6580.597 |
| `bloom_filter` | 8.890 | **8.867** | 9.096 | 1602.638 | 4349.507 |
| `hash_join` | **15.609** | 16.367 | 17.757 | 1891.736 | 4293.140 |
| `sieve` | 12.113 | **11.588** | 11.808 | 45.762 | 1748.088 |
| `fib` | 19.702 | **18.645** | 18.718 | 75.130 | 649.889 |
| `collatz` | 8.961 | **8.895** | 9.169 | 37.794 | 401.554 |
| `matmul` | 19.957 | 19.920 | **19.811** | 53.071 | 1703.045 |
| `json_parse` | **4.971** | 5.377 | 7.377 | 25.725 | 25.123 |
| `nbody` | **16.133** | 23.703 | 16.500 | 57.947 | 1438.363 |
| `chacha20` | **6.516** | 18.971 | 18.625 | n/a | n/a |
| `poly1305` | **8.462** | 25.896 | 15.075 | n/a | n/a |
| `blake2b` | **25.215** | 40.875 | 46.082 | n/a | n/a |
| `sha512` | **29.008** | 31.790 | 30.953 | n/a | n/a |
| `x25519` | **25.553** | 29.392 | 29.765 | n/a | n/a |

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
| _(floor: empty program)_ | _3.452_ | _88.156_ | _**91.608**_ | _49.146_ | _63.033_ | _41.033_ |
| `lcg` | 3.317 | 92.237 | **95.554** | 47.520 | 72.639 | 46.857 |
| `packet_classifier` | 4.031 | 102.935 | **106.966** | 52.622 | 79.347 | 50.347 |
| `ring_write` | 11.047 | 107.392 | **118.439** | 60.079 | 79.037 | 51.851 |
| `histogram_bins` | 10.015 | 98.252 | **108.267** | 55.375 | 81.233 | 51.418 |
| `prefix_scan` | 10.635 | 101.516 | **112.151** | 58.179 | 78.152 | 51.372 |
| `binary_search` | 9.974 | 94.593 | **104.567** | 54.208 | 82.815 | 49.881 |
| `sort_window` | 10.124 | 100.820 | **110.944** | 56.724 | 84.131 | 55.127 |
| `bloom_filter` | 10.534 | 101.572 | **112.106** | 57.566 | 82.781 | 53.408 |
| `hash_join` | 13.134 | 177.806 | **190.940** | 59.832 | 143.767 | 82.276 |
| `sieve` | 10.395 | 101.176 | **111.571** | 57.206 | 81.049 | 55.628 |
| `fib` | 3.710 | 99.723 | **103.433** | 49.810 | 71.398 | 47.167 |
| `collatz` | 3.753 | 100.492 | **104.245** | 50.031 | 78.600 | 48.373 |
| `matmul` | 10.734 | 96.517 | **107.251** | 55.522 | 81.550 | 61.324 |
| `json_parse` | 31.363 | 312.597 | **343.960** | 75.788 | 122.054 | 116.355 |
| `nbody` | 12.102 | 105.180 | **117.282** | 59.098 | 92.473 | 68.820 |
| `chacha20` | 32.756 | 499.833 | **532.589** | 76.935 | 102.196 | 80.178 |
| `poly1305` | 25.726 | 321.828 | **347.554** | 69.527 | 104.095 | 85.775 |
| `blake2b` | 24.323 | 238.132 | **262.455** | 69.162 | 102.451 | 84.014 |
| `sha512` | 23.842 | 287.941 | **311.783** | 68.214 | 98.443 | 74.291 |
| `x25519` | 22.779 | 491.985 | **514.764** | 66.459 | 727.365 | 305.604 |

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
