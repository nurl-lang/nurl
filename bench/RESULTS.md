# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-16T12:38:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `57cc53382f055b43e31df3f97d9ae4c0ae477a46` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38901201981 |
| NURL | `v0.72.0-20-g57cc5338` |
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
| _(floor: empty program)_ | _1.442_ | _1.410_ | _1.638_ | _21.875_ | _17.182_ |
| `lcg` | 39.148 | **39.042** | 39.181 | 1891.386 | 5006.063 |
| `packet_classifier` | 56.140 | **56.022** | 56.280 | 160.976 | 4424.416 |
| `ring_write` | 42.148 | **42.094** | 42.243 | 64.833 | 6567.994 |
| `histogram_bins` | **39.098** | 40.559 | 40.840 | 67.238 | 6162.387 |
| `prefix_scan` | **21.708** | 21.781 | 21.854 | 64.981 | 4432.555 |
| `binary_search` | 39.437 | **37.932** | 40.736 | 105.820 | 6249.866 |
| `sort_window` | 26.590 | **26.570** | 26.770 | 196.371 | 11372.647 |
| `bloom_filter` | **15.333** | 17.798 | 18.301 | 2851.521 | 7505.006 |
| `hash_join` | **26.625** | 27.911 | 29.213 | 3421.618 | 8264.197 |
| `sieve` | 20.192 | 20.109 | **20.097** | 66.865 | 3462.436 |
| `fib` | **25.574** | 29.903 | 30.028 | 132.816 | 1368.611 |
| `collatz` | 12.339 | **12.212** | 12.603 | 49.914 | 741.891 |
| `matmul` | 33.430 | **33.428** | 33.512 | 75.767 | 3491.197 |
| `json_parse` | **8.238** | 8.616 | 11.780 | 35.394 | 38.262 |
| `nbody` | **25.162** | 39.692 | 25.181 | 99.363 | 3104.779 |
| `chacha20` | **7.657** | 42.329 | 33.579 | n/a | n/a |
| `poly1305` | 23.440 | 31.778 | **21.058** | n/a | n/a |
| `blake2b` | **43.579** | 64.972 | 69.021 | n/a | n/a |
| `sha512` | **47.214** | 50.467 | 49.537 | n/a | n/a |
| `x25519` | **44.337** | 48.377 | 49.119 | n/a | n/a |

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
| _(floor: empty program)_ | _4.036_ | _100.175_ | _**104.211**_ | _59.351_ | _78.553_ | _52.136_ |
| `lcg` | 4.129 | 109.776 | **113.905** | 59.327 | 88.403 | 57.974 |
| `packet_classifier` | 4.296 | 109.618 | **113.914** | 59.491 | 90.880 | 58.271 |
| `ring_write` | 12.638 | 113.178 | **125.816** | 68.519 | 90.117 | 59.917 |
| `histogram_bins` | 12.887 | 122.283 | **135.170** | 69.513 | 107.246 | 66.309 |
| `prefix_scan` | 12.974 | 115.811 | **128.785** | 69.650 | 96.502 | 62.814 |
| `binary_search` | 13.161 | 116.101 | **129.262** | 69.871 | 93.253 | 64.271 |
| `sort_window` | 13.267 | 118.139 | **131.406** | 70.372 | 102.277 | 68.670 |
| `bloom_filter` | 13.541 | 119.056 | **132.597** | 69.909 | 101.043 | 66.354 |
| `hash_join` | 17.301 | 265.012 | **282.313** | 74.883 | 219.386 | 113.441 |
| `sieve` | 13.142 | 115.260 | **128.402** | 70.175 | 103.120 | 69.226 |
| `fib` | 4.363 | 112.462 | **116.825** | 61.388 | 90.690 | 59.223 |
| `collatz` | 4.404 | 116.763 | **121.167** | 62.055 | 92.524 | 61.024 |
| `matmul` | 14.398 | 116.702 | **131.100** | 70.954 | 104.454 | 78.621 |
| `json_parse` | 44.519 | 485.437 | **529.956** | 102.825 | 158.619 | 154.750 |
| `nbody` | 15.537 | 134.779 | **150.316** | 72.551 | 127.639 | 93.929 |
| `chacha20` | 45.180 | 775.984 | **821.164** | 102.851 | 144.430 | 104.324 |
| `poly1305` | 30.078 | 267.895 | **297.973** | 87.176 | 140.613 | 119.428 |
| `blake2b` | 33.927 | 379.803 | **413.730** | 90.122 | 144.811 | 114.021 |
| `sha512` | 34.070 | 477.061 | **511.131** | 92.940 | 138.767 | 100.361 |
| `x25519` | 38.432 | 716.263 | **754.695** | 95.409 | 1215.684 | 492.645 |

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
