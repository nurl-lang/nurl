# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T17:02:26Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz (4 logical cores) |
| Memory | 16366512 KiB |
| Commit | `0035da8acc71cfa42625ad414bbf9099ff29c86e` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40916462938 |
| NURL | `v0.80.0-67-g0035da8a` |
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
| _(floor: empty program)_ | _1.272_ | _1.253_ | _1.435_ | _24.955_ | _16.712_ |
| `lcg` | **37.708** | 37.792 | 37.812 | 1812.328 | 5280.083 |
| `packet_classifier` | **52.829** | 52.878 | 53.051 | 158.070 | 4472.243 |
| `ring_write` | 40.782 | **40.646** | 41.119 | 70.210 | 6228.013 |
| `histogram_bins` | 40.754 | **39.547** | 41.173 | 69.266 | 6069.761 |
| `prefix_scan` | 21.517 | 21.491 | **20.912** | 68.687 | 4594.365 |
| `binary_search` | 35.117 | **30.178** | 37.021 | 107.151 | 6050.563 |
| `sort_window` | 35.858 | **35.132** | 35.889 | 182.104 | 11284.488 |
| `bloom_filter` | 14.506 | 14.295 | **13.962** | 2882.557 | 7650.941 |
| `hash_join` | **25.318** | 25.351 | 26.999 | 3507.031 | 8054.600 |
| `sieve` | 38.022 | **37.051** | 37.572 | 86.473 | 3731.105 |
| `fib` | **25.993** | 26.640 | 26.790 | 121.873 | 1172.631 |
| `collatz` | 13.048 | **12.774** | 12.961 | 58.483 | 687.481 |
| `matmul` | 17.562 | **17.518** | 17.574 | 75.444 | 3255.499 |
| `json_parse` | **7.412** | 7.828 | 10.018 | 35.868 | 37.166 |
| `nbody` | 21.956 | 35.489 | **21.873** | 93.162 | 2431.807 |
| `chacha20` | **7.674** | 38.040 | 33.475 | n/a | n/a |
| `poly1305` | **12.221** | 34.382 | 25.874 | n/a | n/a |
| `blake2b` | **44.746** | 58.457 | 66.570 | n/a | n/a |
| `sha512` | **45.620** | 47.930 | 49.177 | n/a | n/a |
| `x25519` | **30.268** | 48.481 | 49.889 | n/a | n/a |

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
| _(floor: empty program)_ | _4.103_ | _106.422_ | _**110.525**_ | _57.515_ | _72.687_ | _55.012_ |
| `lcg` | 4.273 | 119.635 | **123.908** | 57.978 | 82.555 | 63.526 |
| `packet_classifier` | 4.436 | 118.836 | **123.272** | 57.507 | 82.366 | 64.709 |
| `ring_write` | 14.532 | 119.019 | **133.551** | 66.400 | 83.566 | 65.709 |
| `histogram_bins` | 14.417 | 118.306 | **132.723** | 66.055 | 99.048 | 71.452 |
| `prefix_scan` | 14.987 | 118.952 | **133.939** | 67.004 | 87.818 | 67.781 |
| `binary_search` | 14.763 | 118.091 | **132.854** | 66.898 | 84.330 | 69.948 |
| `sort_window` | 14.755 | 120.122 | **134.877** | 66.802 | 91.415 | 72.866 |
| `bloom_filter` | 15.411 | 122.450 | **137.861** | 67.034 | 90.696 | 69.611 |
| `hash_join` | 18.686 | 240.805 | **259.491** | 71.040 | 197.362 | 116.448 |
| `sieve` | 14.885 | 119.830 | **134.715** | 67.106 | 92.588 | 75.637 |
| `fib` | 4.583 | 118.233 | **122.816** | 57.853 | 82.429 | 63.321 |
| `collatz` | 4.575 | 119.509 | **124.084** | 57.653 | 84.230 | 63.104 |
| `matmul` | 16.401 | 121.976 | **138.377** | 69.144 | 95.705 | 84.602 |
| `json_parse` | 47.934 | 434.769 | **482.703** | 101.754 | 147.106 | 172.728 |
| `nbody` | 17.390 | 127.176 | **144.566** | 70.416 | 116.016 | 103.055 |
| `chacha20` | 53.568 | 722.860 | **776.428** | 108.103 | 129.392 | 113.502 |
| `poly1305` | 41.012 | 488.051 | **529.063** | 94.027 | 130.339 | 126.200 |
| `blake2b` | 37.302 | 355.129 | **392.431** | 90.791 | 133.932 | 124.234 |
| `sha512` | 37.105 | 435.310 | **472.415** | 89.774 | 123.908 | 109.296 |
| `x25519` | 50.010 | 1259.408 | **1309.418** | 103.041 | 1218.536 | 500.063 |

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
