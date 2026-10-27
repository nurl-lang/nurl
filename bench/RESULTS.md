# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T21:07:12Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `f1446bbdc2e030c4168289825b48f91aaf579c95` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40583155903 |
| NURL | `v0.79.1` |
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
| _(floor: empty program)_ | _1.448_ | _1.429_ | _1.627_ | _21.359_ | _17.068_ |
| `lcg` | 39.108 | **39.026** | 39.130 | 1903.640 | 5105.266 |
| `packet_classifier` | 56.170 | **56.132** | 56.495 | 161.056 | 4297.258 |
| `ring_write` | **42.166** | 42.201 | 42.358 | 65.655 | 6599.622 |
| `histogram_bins` | **40.504** | 40.608 | 40.723 | 64.813 | 6120.559 |
| `prefix_scan` | **21.520** | 21.578 | 21.850 | 65.439 | 4571.944 |
| `binary_search` | 38.190 | **38.090** | 40.903 | 104.848 | 6059.986 |
| `sort_window` | 26.517 | **26.448** | 26.780 | 197.301 | 12182.856 |
| `bloom_filter` | **15.365** | 17.921 | 18.654 | 2847.389 | 7480.616 |
| `hash_join` | **26.892** | 28.042 | 29.173 | 3386.463 | 8293.426 |
| `sieve` | 19.898 | 20.064 | **19.678** | 66.706 | 3188.441 |
| `fib` | 29.851 | **29.826** | 29.879 | 131.621 | 1352.359 |
| `collatz` | 12.240 | **12.153** | 12.399 | 49.569 | 740.930 |
| `matmul` | 33.516 | **33.347** | 33.446 | 75.602 | 3147.290 |
| `json_parse` | **8.099** | 8.530 | 11.743 | 34.694 | 38.167 |
| `nbody` | **25.221** | 39.653 | 25.274 | 100.161 | 3147.689 |
| `chacha20` | **7.323** | 41.853 | 33.586 | n/a | n/a |
| `poly1305` | **11.681** | 31.778 | 21.122 | n/a | n/a |
| `blake2b` | **43.691** | 64.912 | 68.881 | n/a | n/a |
| `sha512` | **46.208** | 50.587 | 49.441 | n/a | n/a |
| `x25519` | **44.510** | 48.563 | 49.489 | n/a | n/a |

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
| _(floor: empty program)_ | _4.304_ | _110.364_ | _**114.668**_ | _59.900_ | _79.261_ | _52.988_ |
| `lcg` | 4.378 | 122.724 | **127.102** | 60.841 | 86.390 | 57.115 |
| `packet_classifier` | 4.543 | 123.256 | **127.799** | 60.606 | 87.959 | 58.382 |
| `ring_write` | 15.162 | 127.107 | **142.269** | 71.340 | 88.266 | 59.288 |
| `histogram_bins` | 15.302 | 126.750 | **142.052** | 71.525 | 104.910 | 66.517 |
| `prefix_scan` | 15.380 | 128.679 | **144.059** | 71.494 | 93.887 | 62.160 |
| `binary_search` | 15.555 | 127.023 | **142.578** | 71.792 | 88.882 | 63.776 |
| `sort_window` | 15.706 | 131.775 | **147.481** | 71.948 | 99.562 | 68.830 |
| `bloom_filter` | 16.215 | 128.990 | **145.205** | 71.028 | 99.935 | 68.419 |
| `hash_join` | 19.812 | 259.168 | **278.980** | 74.777 | 212.891 | 109.601 |
| `sieve` | 15.542 | 128.038 | **143.580** | 72.041 | 98.649 | 68.636 |
| `fib` | 4.638 | 121.516 | **126.154** | 60.881 | 88.294 | 58.144 |
| `collatz` | 4.885 | 126.343 | **131.228** | 61.268 | 87.864 | 58.471 |
| `matmul` | 17.016 | 129.009 | **146.025** | 73.399 | 102.574 | 78.456 |
| `json_parse` | 50.412 | 483.292 | **533.704** | 106.621 | 157.505 | 154.648 |
| `nbody` | 17.928 | 135.239 | **153.167** | 73.921 | 123.241 | 93.409 |
| `chacha20` | 57.224 | 748.024 | **805.248** | 113.649 | 137.737 | 105.242 |
| `poly1305` | 43.870 | 505.251 | **549.121** | 100.364 | 138.623 | 119.396 |
| `blake2b` | 39.326 | 376.127 | **415.453** | 95.448 | 142.262 | 114.780 |
| `sha512` | 38.973 | 469.921 | **508.894** | 95.218 | 134.402 | 100.123 |
| `x25519` | 38.798 | 821.671 | **860.469** | 93.442 | 1209.580 | 486.701 |

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
