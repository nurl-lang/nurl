# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-30T21:25:35Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e8bb78830d0ba41ae188d0302d29da7e6f708c25` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41130219281 |
| NURL | `v0.81.0-13-ge8bb7883` |
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
| _(floor: empty program)_ | _3.702_ | _3.697_ | _3.857_ | _29.051_ | _15.937_ |
| `lcg` | 41.903 | **41.784** | 42.029 | 1796.269 | 4926.242 |
| `packet_classifier` | 59.268 | **59.222** | 59.389 | 167.779 | 4203.981 |
| `ring_write` | 44.878 | **44.763** | 45.059 | 71.914 | 6151.443 |
| `histogram_bins` | **42.340** | 43.435 | 43.497 | 73.305 | 5833.350 |
| `prefix_scan` | 24.480 | **24.468** | 24.760 | 71.825 | 4218.335 |
| `binary_search` | 42.092 | **40.832** | 43.418 | 112.599 | 5939.517 |
| `sort_window` | 28.787 | **28.661** | 28.890 | 200.076 | 11751.784 |
| `bloom_filter` | **19.318** | 20.509 | 21.446 | 2888.086 | 7038.348 |
| `hash_join` | 29.389 | **28.956** | 31.988 | 3379.856 | 7616.598 |
| `sieve` | 27.601 | **26.774** | 27.182 | 75.673 | 3119.091 |
| `fib` | **27.202** | 32.153 | 32.230 | 135.727 | 1097.485 |
| `collatz` | 14.419 | **14.254** | 14.504 | 56.480 | 687.063 |
| `matmul` | 36.179 | **35.754** | 36.548 | 75.679 | 3346.285 |
| `json_parse` | **10.538** | 13.380 | 18.712 | 39.665 | 36.836 |
| `nbody` | **26.658** | 42.202 | 27.887 | 105.999 | 3001.860 |
| `chacha20` | **9.454** | 44.971 | 35.898 | n/a | n/a |
| `poly1305` | **14.079** | 34.236 | 23.601 | n/a | n/a |
| `blake2b` | **46.372** | 66.903 | 71.374 | n/a | n/a |
| `sha512` | **49.817** | 49.858 | 51.680 | n/a | n/a |
| `x25519` | **34.264** | 51.618 | 52.059 | n/a | n/a |

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
| _(floor: empty program)_ | _7.203_ | _123.020_ | _**130.223**_ | _69.537_ | _85.820_ | _69.036_ |
| `lcg` | 7.111 | 130.783 | **137.894** | 68.004 | 95.749 | 75.129 |
| `packet_classifier` | 7.258 | 132.477 | **139.735** | 68.785 | 98.260 | 79.849 |
| `ring_write` | 17.872 | 132.367 | **150.239** | 79.002 | 96.771 | 78.279 |
| `histogram_bins` | 18.439 | 138.870 | **157.309** | 79.290 | 143.992 | 83.693 |
| `prefix_scan` | 18.318 | 133.491 | **151.809** | 78.838 | 101.631 | 81.736 |
| `binary_search` | 18.024 | 131.591 | **149.615** | 75.925 | 95.434 | 82.034 |
| `sort_window` | 18.537 | 142.555 | **161.092** | 81.404 | 110.453 | 89.628 |
| `bloom_filter` | 18.651 | 136.439 | **155.090** | 76.925 | 104.769 | 82.131 |
| `hash_join` | 22.037 | 270.227 | **292.264** | 82.914 | 221.900 | 128.478 |
| `sieve` | 17.753 | 130.666 | **148.419** | 76.239 | 107.948 | 87.640 |
| `fib` | 7.503 | 134.204 | **141.707** | 69.064 | 93.808 | 73.599 |
| `collatz` | 7.232 | 129.841 | **137.073** | 66.478 | 92.740 | 74.217 |
| `matmul` | 19.578 | 132.090 | **151.668** | 77.723 | 109.113 | 97.124 |
| `json_parse` | 53.208 | 457.009 | **510.217** | 112.540 | 161.820 | 180.135 |
| `nbody` | 20.604 | 137.605 | **158.209** | 79.284 | 130.970 | 112.941 |
| `chacha20` | 60.201 | 799.059 | **859.260** | 121.746 | 149.742 | 129.220 |
| `poly1305` | 46.619 | 511.061 | **557.680** | 107.309 | 150.119 | 141.129 |
| `blake2b` | 42.843 | 405.799 | **448.642** | 105.748 | 151.862 | 137.745 |
| `sha512` | 41.626 | 461.704 | **503.330** | 101.766 | 141.767 | 119.827 |
| `x25519` | 56.284 | 1549.033 | **1605.317** | 116.582 | 1263.153 | 518.062 |

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
