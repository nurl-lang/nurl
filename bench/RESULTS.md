# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T04:41:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `ed7d3e5fbb70c0cf9bc8d29d7cd2b87221de5c03` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40633137367 |
| NURL | `v0.79.1-13-ged7d3e5f` |
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
| _(floor: empty program)_ | _1.476_ | _1.438_ | _1.620_ | _26.018_ | _18.119_ |
| `lcg` | **38.988** | 39.172 | 39.407 | 1890.591 | 5354.107 |
| `packet_classifier` | 56.346 | **56.236** | 56.477 | 161.917 | 4344.191 |
| `ring_write` | **42.192** | 42.337 | 42.428 | 66.127 | 6292.455 |
| `histogram_bins` | **40.495** | 40.652 | 40.837 | 66.923 | 6254.943 |
| `prefix_scan` | **21.615** | 21.670 | 21.875 | 65.661 | 4528.562 |
| `binary_search` | 38.103 | **38.004** | 40.944 | 105.843 | 5918.954 |
| `sort_window` | **26.472** | 26.561 | 26.771 | 197.237 | 13471.769 |
| `bloom_filter` | **15.382** | 17.906 | 18.369 | 2864.626 | 7638.447 |
| `hash_join` | **26.894** | 27.711 | 29.106 | 3394.856 | 8269.223 |
| `sieve` | 20.445 | **20.113** | 20.214 | 68.277 | 3353.909 |
| `fib` | **29.657** | 29.808 | 30.005 | 131.247 | 1356.957 |
| `collatz` | 12.213 | **12.160** | 12.448 | 53.010 | 729.550 |
| `matmul` | 33.716 | **33.436** | 33.712 | 77.248 | 3121.417 |
| `json_parse` | **8.190** | 8.701 | 11.791 | 35.855 | 39.135 |
| `nbody` | 25.516 | 39.927 | **25.318** | 100.957 | 3180.234 |
| `chacha20` | **7.452** | 42.272 | 33.638 | n/a | n/a |
| `poly1305` | **11.748** | 31.731 | 21.038 | n/a | n/a |
| `blake2b` | **43.491** | 64.883 | 69.102 | n/a | n/a |
| `sha512` | **47.019** | 50.596 | 49.517 | n/a | n/a |
| `x25519` | **44.169** | 48.305 | 49.263 | n/a | n/a |

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
| _(floor: empty program)_ | _4.364_ | _116.184_ | _**120.548**_ | _62.918_ | _85.270_ | _53.579_ |
| `lcg` | 4.557 | 130.113 | **134.670** | 63.050 | 91.827 | 57.655 |
| `packet_classifier` | 4.588 | 128.840 | **133.428** | 63.184 | 93.255 | 58.760 |
| `ring_write` | 15.268 | 130.900 | **146.168** | 72.614 | 93.408 | 61.084 |
| `histogram_bins` | 15.204 | 129.706 | **144.910** | 71.922 | 108.610 | 66.872 |
| `prefix_scan` | 15.364 | 130.528 | **145.892** | 72.287 | 97.634 | 63.288 |
| `binary_search` | 15.479 | 127.498 | **142.977** | 72.257 | 92.763 | 64.023 |
| `sort_window` | 15.467 | 129.141 | **144.608** | 71.106 | 102.381 | 69.030 |
| `bloom_filter` | 16.270 | 131.677 | **147.947** | 72.252 | 101.110 | 65.425 |
| `hash_join` | 19.711 | 266.255 | **285.966** | 75.762 | 218.277 | 109.355 |
| `sieve` | 15.331 | 128.612 | **143.943** | 72.005 | 102.409 | 69.612 |
| `fib` | 4.654 | 126.483 | **131.137** | 62.348 | 89.150 | 58.141 |
| `collatz` | 4.815 | 129.426 | **134.241** | 62.212 | 91.529 | 58.935 |
| `matmul` | 17.230 | 131.364 | **148.594** | 74.962 | 107.029 | 79.596 |
| `json_parse` | 50.817 | 497.027 | **547.844** | 109.221 | 162.454 | 157.067 |
| `nbody` | 18.084 | 138.228 | **156.312** | 75.099 | 130.136 | 95.427 |
| `chacha20` | 58.320 | 761.824 | **820.144** | 116.168 | 141.110 | 105.865 |
| `poly1305` | 43.356 | 515.911 | **559.267** | 101.255 | 142.438 | 119.970 |
| `blake2b` | 39.807 | 383.155 | **422.962** | 97.651 | 147.816 | 115.601 |
| `sha512` | 39.189 | 478.139 | **517.328** | 96.547 | 139.328 | 100.894 |
| `x25519` | 39.009 | 836.667 | **875.676** | 96.423 | 1225.223 | 492.505 |

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
