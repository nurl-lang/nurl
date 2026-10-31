# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T02:02:02Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `bd3f23719bbc005e96a81059da3cfe4d8348a3b4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41157659490 |
| NURL | `v0.81.0-34-gbd3f2371` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.1 |
| Python | Python 3.14.4 |

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
| _(floor: empty program)_ | _3.605_ | _3.587_ | _3.837_ | _29.982_ | _15.369_ |
| `lcg` | 41.583 | **41.442** | 41.679 | 1791.535 | 4898.585 |
| `packet_classifier` | 58.823 | **58.688** | 58.908 | 169.052 | 4249.598 |
| `ring_write` | 44.710 | **44.588** | 44.825 | 71.799 | 6141.355 |
| `histogram_bins` | **42.007** | 43.094 | 43.334 | 71.925 | 5817.784 |
| `prefix_scan` | **24.017** | 24.050 | 24.324 | 69.813 | 4212.761 |
| `binary_search` | 42.042 | **40.910** | 43.485 | 112.151 | 6105.108 |
| `sort_window` | 29.000 | **28.895** | 29.035 | 199.839 | 11915.661 |
| `bloom_filter` | **19.114** | 20.410 | 20.933 | 2854.190 | 7083.601 |
| `hash_join` | **28.721** | 28.836 | 31.108 | 3354.292 | 7674.657 |
| `sieve` | **25.360** | 26.806 | 26.989 | 75.029 | 3418.592 |
| `fib` | **27.729** | 32.265 | 32.393 | 136.106 | 1128.040 |
| `collatz` | 14.839 | **14.684** | 14.986 | 55.647 | 694.645 |
| `matmul` | 36.414 | **36.269** | 36.549 | 76.151 | 3055.284 |
| `json_parse` | **10.397** | 13.177 | 18.407 | 39.644 | 37.063 |
| `nbody` | **26.248** | 41.774 | 27.360 | 104.399 | 3014.082 |
| `chacha20` | **9.252** | 43.719 | 35.910 | n/a | n/a |
| `poly1305` | **13.700** | 34.276 | 23.780 | n/a | n/a |
| `blake2b` | **46.323** | 66.949 | 71.548 | n/a | n/a |
| `sha512` | **49.991** | 50.016 | 52.196 | n/a | n/a |
| `x25519` | **33.634** | 51.107 | 51.614 | n/a | n/a |

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
| _(floor: empty program)_ | _6.771_ | _122.845_ | _**129.616**_ | _66.520_ | _81.845_ | _70.786_ |
| `lcg` | 6.799 | 132.369 | **139.168** | 65.525 | 95.375 | 73.227 |
| `packet_classifier` | 6.881 | 134.178 | **141.059** | 67.027 | 95.944 | 75.539 |
| `ring_write` | 17.371 | 136.615 | **153.986** | 77.211 | 97.206 | 77.252 |
| `histogram_bins` | 17.868 | 138.258 | **156.126** | 77.710 | 140.380 | 83.572 |
| `prefix_scan` | 17.711 | 137.011 | **154.722** | 77.246 | 101.812 | 80.216 |
| `binary_search` | 17.980 | 136.412 | **154.392** | 77.723 | 98.043 | 81.176 |
| `sort_window` | 18.270 | 140.180 | **158.450** | 78.102 | 107.069 | 86.535 |
| `bloom_filter` | 18.415 | 138.476 | **156.891** | 76.199 | 109.004 | 81.889 |
| `hash_join` | 21.529 | 271.972 | **293.501** | 80.274 | 224.497 | 131.189 |
| `sieve` | 17.956 | 138.756 | **156.712** | 79.345 | 110.064 | 86.938 |
| `fib` | 7.104 | 136.377 | **143.481** | 65.919 | 91.098 | 75.183 |
| `collatz` | 7.392 | 141.015 | **148.407** | 69.512 | 100.227 | 78.819 |
| `matmul` | 18.698 | 139.754 | **158.452** | 78.533 | 115.341 | 101.675 |
| `json_parse` | 51.519 | 457.747 | **509.266** | 111.356 | 161.490 | 179.514 |
| `nbody` | 19.868 | 140.918 | **160.786** | 78.292 | 129.596 | 114.165 |
| `chacha20` | 58.495 | 788.457 | **846.952** | 117.879 | 144.749 | 124.901 |
| `poly1305` | 45.941 | 512.489 | **558.430** | 106.307 | 150.311 | 142.192 |
| `blake2b` | 41.589 | 342.565 | **384.154** | 101.406 | 152.250 | 133.894 |
| `sha512` | 41.808 | 468.437 | **510.245** | 103.103 | 146.802 | 124.688 |
| `x25519` | 57.319 | 1580.606 | **1637.925** | 118.875 | 1247.901 | 517.675 |

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
