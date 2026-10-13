# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-13T04:07:40Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e92a23859037d5ceb13928d38357cdaff5ab754a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38344556154 |
| NURL | `v0.72.0-10-ge92a2385` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
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
| _(floor: empty program)_ | _1.205_ | _1.189_ | _1.349_ | _20.875_ | _13.750_ |
| `lcg` | **34.243** | 34.289 | 34.346 | 1411.897 | 4108.016 |
| `packet_classifier` | **49.179** | 49.242 | 49.460 | 123.602 | 3542.139 |
| `ring_write` | **36.925** | 36.956 | 37.100 | 58.890 | 5008.070 |
| `histogram_bins` | **34.560** | 34.565 | 34.746 | 59.671 | 4921.842 |
| `prefix_scan` | 18.933 | **18.918** | 19.140 | 56.821 | 3763.981 |
| `binary_search` | 32.320 | **27.902** | 33.711 | 88.304 | 5060.007 |
| `sort_window` | **23.199** | **23.199** | 23.322 | 127.546 | 9034.630 |
| `bloom_filter` | **13.366** | 14.459 | 16.007 | 2146.914 | 5914.570 |
| `hash_join` | **21.346** | 22.144 | 23.347 | 2670.408 | 6474.672 |
| `sieve` | 15.989 | **15.479** | 15.616 | 55.584 | 2944.420 |
| `fib` | **21.522** | 25.650 | 25.853 | 110.511 | 1007.930 |
| `collatz` | 10.560 | **10.555** | 10.814 | 39.982 | 583.840 |
| `matmul` | 35.454 | **35.182** | 35.518 | 65.640 | 2765.214 |
| `json_parse` | **6.226** | 6.822 | 9.414 | 30.301 | 30.192 |
| `nbody` | **20.747** | 34.808 | 20.758 | 76.180 | 2586.070 |
| `chacha20` | **7.051** | 35.696 | 27.535 | n/a | n/a |
| `poly1305` | 20.356 | 31.178 | **18.471** | n/a | n/a |
| `blake2b` | **37.789** | 55.897 | 60.574 | n/a | n/a |
| `sha512` | **38.520** | 40.071 | 42.229 | n/a | n/a |
| `x25519` | **38.068** | 41.988 | 43.276 | n/a | n/a |

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
| _(floor: empty program)_ | _3.710_ | _90.139_ | _**93.849**_ | _55.809_ | _69.492_ | _50.947_ |
| `lcg` | 3.769 | 95.133 | **98.902** | 53.832 | 81.604 | 57.396 |
| `packet_classifier` | 3.738 | 95.591 | **99.329** | 54.504 | 83.204 | 59.072 |
| `ring_write` | 10.444 | 99.334 | **109.778** | 60.908 | 81.681 | 59.486 |
| `histogram_bins` | 10.900 | 105.327 | **116.227** | 62.192 | 94.589 | 65.943 |
| `prefix_scan` | 11.061 | 102.958 | **114.019** | 61.910 | 85.361 | 62.597 |
| `binary_search` | 10.702 | 101.093 | **111.795** | 62.026 | 84.095 | 64.846 |
| `sort_window` | 11.332 | 106.257 | **117.589** | 63.881 | 93.916 | 68.025 |
| `bloom_filter` | 10.988 | 100.349 | **111.337** | 60.995 | 86.448 | 64.452 |
| `hash_join` | 13.924 | 204.396 | **218.320** | 63.875 | 169.334 | 98.397 |
| `sieve` | 10.937 | 98.362 | **109.299** | 60.999 | 86.927 | 68.732 |
| `fib` | 3.811 | 94.749 | **98.560** | 53.470 | 78.254 | 58.205 |
| `collatz` | 3.927 | 98.380 | **102.307** | 53.348 | 79.238 | 60.332 |
| `matmul` | 11.807 | 99.929 | **111.736** | 62.378 | 89.062 | 74.165 |
| `json_parse` | 32.961 | 366.196 | **399.157** | 83.919 | 130.025 | 173.157 |
| `nbody` | 12.623 | 113.283 | **125.906** | 62.339 | 104.817 | 89.100 |
| `chacha20` | 34.711 | 476.558 | **511.269** | 85.368 | 114.950 | 98.310 |
| `poly1305` | 23.264 | 210.822 | **234.086** | 73.240 | 115.818 | 109.099 |
| `blake2b` | 25.003 | 278.496 | **303.499** | 76.149 | 119.663 | 104.828 |
| `sha512` | 25.114 | 358.359 | **383.473** | 75.653 | 113.145 | 93.115 |
| `x25519` | 29.844 | 546.768 | **576.612** | 80.869 | 942.168 | 395.511 |

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
