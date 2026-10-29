# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T19:15:33Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `cf63043116b07036a0227ee1c053f6eeb7a82f05` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40937607866 |
| NURL | `v0.80.0-73-gcf630431` |
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
| _(floor: empty program)_ | _1.296_ | _1.259_ | _1.456_ | _19.165_ | _13.907_ |
| `lcg` | **34.331** | 34.342 | 34.516 | 1421.740 | 4110.964 |
| `packet_classifier` | 49.393 | **49.343** | 49.545 | 124.883 | 4026.879 |
| `ring_write` | **37.046** | 37.114 | 37.304 | 59.165 | 5031.067 |
| `histogram_bins` | 34.663 | **34.661** | 34.852 | 59.482 | 4776.952 |
| `prefix_scan` | **19.142** | **19.142** | 19.324 | 58.471 | 3762.181 |
| `binary_search` | 32.437 | **27.832** | 33.740 | 88.110 | 5511.100 |
| `sort_window` | **23.421** | 23.432 | 23.693 | 131.507 | 9013.556 |
| `bloom_filter` | **13.845** | 14.743 | 16.376 | 2160.309 | 6375.366 |
| `hash_join` | **21.727** | 22.453 | 23.744 | 2641.466 | 6800.906 |
| `sieve` | 20.437 | **19.419** | 19.597 | 61.671 | 2733.802 |
| `fib` | **21.808** | 25.938 | 26.103 | 113.398 | 998.965 |
| `collatz` | 10.803 | **10.751** | 11.058 | 43.214 | 590.268 |
| `matmul` | **35.078** | 35.582 | 35.431 | 68.437 | 2559.044 |
| `json_parse` | **6.409** | 7.068 | 9.682 | 32.151 | 32.414 |
| `nbody` | 21.104 | 35.121 | **21.100** | 79.422 | 2567.118 |
| `chacha20` | **6.899** | 35.986 | 28.043 | n/a | n/a |
| `poly1305` | **10.229** | 31.493 | 18.813 | n/a | n/a |
| `blake2b` | **38.410** | 55.954 | 60.761 | n/a | n/a |
| `sha512` | **38.823** | 40.318 | 42.551 | n/a | n/a |
| `x25519` | **27.848** | 42.219 | 43.539 | n/a | n/a |

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
| _(floor: empty program)_ | _4.150_ | _101.169_ | _**105.319**_ | _57.456_ | _76.275_ | _56.596_ |
| `lcg` | 4.353 | 111.378 | **115.731** | 57.569 | 83.014 | 61.915 |
| `packet_classifier` | 4.343 | 112.533 | **116.876** | 57.308 | 86.027 | 62.442 |
| `ring_write` | 12.837 | 112.865 | **125.702** | 64.570 | 85.166 | 63.951 |
| `histogram_bins` | 13.047 | 117.198 | **130.245** | 66.246 | 99.449 | 69.962 |
| `prefix_scan` | 13.173 | 115.442 | **128.615** | 65.787 | 90.598 | 67.275 |
| `binary_search` | 13.344 | 115.041 | **128.385** | 66.302 | 88.107 | 69.237 |
| `sort_window` | 13.384 | 119.699 | **133.083** | 66.647 | 96.186 | 74.681 |
| `bloom_filter` | 13.948 | 121.215 | **135.163** | 68.621 | 97.625 | 72.888 |
| `hash_join` | 16.923 | 216.972 | **233.895** | 71.923 | 180.762 | 111.684 |
| `sieve` | 13.627 | 119.580 | **133.207** | 68.700 | 96.955 | 78.356 |
| `fib` | 4.547 | 120.612 | **125.159** | 61.638 | 89.106 | 68.068 |
| `collatz` | 4.812 | 122.590 | **127.402** | 62.094 | 89.714 | 67.045 |
| `matmul` | 14.678 | 120.534 | **135.212** | 70.178 | 99.273 | 86.880 |
| `json_parse` | 42.285 | 379.111 | **421.396** | 100.512 | 141.060 | 152.467 |
| `nbody` | 15.888 | 125.412 | **141.300** | 71.073 | 115.480 | 102.632 |
| `chacha20` | 47.142 | 609.546 | **656.688** | 104.113 | 125.960 | 109.404 |
| `poly1305` | 36.568 | 420.686 | **457.254** | 93.352 | 127.009 | 119.771 |
| `blake2b` | 32.773 | 305.433 | **338.206** | 89.355 | 130.747 | 117.019 |
| `sha512` | 32.407 | 375.151 | **407.558** | 89.306 | 124.453 | 106.434 |
| `x25519` | 45.009 | 999.648 | **1044.657** | 101.764 | 962.664 | 418.141 |

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
