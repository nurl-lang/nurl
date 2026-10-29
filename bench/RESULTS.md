# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T08:49:50Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16366512 KiB |
| Commit | `e9ae55df014eddf36361b0f624e322dda6e06056` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40844299550 |
| NURL | `v0.80.0-47-ge9ae55df` |
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
| _(floor: empty program)_ | _1.330_ | _1.322_ | _1.443_ | _21.011_ | _14.241_ |
| `lcg` | 35.589 | **35.551** | 35.731 | 1216.239 | 3676.392 |
| `packet_classifier` | 61.391 | **61.321** | 61.500 | 150.142 | 3025.156 |
| `ring_write` | **38.664** | 39.146 | 38.770 | 63.218 | 4324.393 |
| `histogram_bins` | 36.917 | **36.862** | 37.048 | 63.016 | 4102.864 |
| `prefix_scan` | 19.816 | **19.726** | 20.187 | 60.569 | 3046.255 |
| `binary_search` | 32.483 | **26.468** | 34.138 | 99.875 | 4691.308 |
| `sort_window` | 35.591 | **35.575** | 36.437 | 160.556 | 7870.178 |
| `bloom_filter` | **12.680** | 12.773 | 12.966 | 2092.748 | 5535.774 |
| `hash_join` | **21.696** | 22.646 | 23.016 | 2584.562 | 6134.402 |
| `sieve` | **38.906** | 40.268 | 40.241 | 83.754 | 2415.178 |
| `fib` | **20.817** | 24.147 | 24.302 | 101.023 | 783.769 |
| `collatz` | **13.344** | 13.531 | 14.530 | 53.786 | 495.757 |
| `matmul` | 17.538 | **17.483** | 18.145 | 69.274 | 2164.722 |
| `json_parse` | **6.090** | 7.005 | 8.551 | 30.143 | 30.159 |
| `nbody` | **19.624** | 27.047 | 19.636 | 75.539 | 1874.579 |
| `chacha20` | **7.269** | 32.788 | 28.499 | n/a | n/a |
| `poly1305` | **12.016** | 30.226 | 22.159 | n/a | n/a |
| `blake2b` | **37.956** | 45.935 | 47.805 | n/a | n/a |
| `sha512` | **37.185** | 41.162 | 46.041 | n/a | n/a |
| `x25519` | **25.327** | 36.849 | 36.261 | n/a | n/a |

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
| _(floor: empty program)_ | _4.287_ | _100.330_ | _**104.617**_ | _55.555_ | _70.956_ | _57.596_ |
| `lcg` | 4.216 | 109.484 | **113.700** | 54.802 | 78.508 | 65.506 |
| `packet_classifier` | 4.348 | 109.437 | **113.785** | 54.842 | 79.889 | 66.691 |
| `ring_write` | 13.107 | 110.502 | **123.609** | 63.488 | 80.484 | 68.239 |
| `histogram_bins` | 12.981 | 110.194 | **123.175** | 62.917 | 92.133 | 73.314 |
| `prefix_scan` | 13.409 | 113.429 | **126.838** | 64.417 | 85.031 | 69.747 |
| `binary_search` | 13.496 | 113.429 | **126.925** | 64.177 | 82.386 | 72.024 |
| `sort_window` | 13.492 | 116.378 | **129.870** | 64.614 | 92.163 | 75.658 |
| `bloom_filter` | 13.874 | 116.730 | **130.604** | 65.078 | 89.679 | 74.214 |
| `hash_join` | 16.517 | 210.357 | **226.874** | 68.212 | 171.704 | 111.444 |
| `sieve` | 13.352 | 112.274 | **125.626** | 64.923 | 90.233 | 78.509 |
| `fib` | 4.336 | 108.909 | **113.245** | 54.651 | 78.603 | 63.822 |
| `collatz` | 4.475 | 111.076 | **115.551** | 55.825 | 79.048 | 64.880 |
| `matmul` | 14.065 | 110.382 | **124.447** | 63.746 | 88.807 | 84.817 |
| `json_parse` | 40.991 | 369.501 | **410.492** | 92.805 | 134.788 | 160.931 |
| `nbody` | 15.025 | 115.961 | **130.986** | 64.706 | 104.684 | 97.874 |
| `chacha20` | 44.938 | 598.484 | **643.422** | 96.628 | 117.992 | 110.347 |
| `poly1305` | 34.852 | 407.589 | **442.441** | 85.800 | 126.343 | 120.695 |
| `blake2b` | 31.935 | 300.451 | **332.386** | 83.827 | 122.987 | 125.511 |
| `sha512` | 32.168 | 372.334 | **404.502** | 83.585 | 118.696 | 107.474 |
| `x25519` | 42.588 | 1045.037 | **1087.625** | 95.801 | 1016.488 | 433.190 |

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
