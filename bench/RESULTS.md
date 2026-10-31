# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T10:32:46Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `b516ff3cb87159d16449fe41d53b7b5391fc0233` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41192774217 |
| NURL | `v0.82.0-26-gb516ff3c` |
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
| _(floor: empty program)_ | _3.303_ | _3.304_ | _3.470_ | _26.467_ | _14.947_ |
| `lcg` | **41.174** | 41.305 | 41.506 | 1787.947 | 4897.391 |
| `packet_classifier` | 58.777 | **58.585** | 58.811 | 167.750 | 4089.390 |
| `ring_write` | 44.708 | **44.524** | 44.802 | 71.026 | 6069.613 |
| `histogram_bins` | **42.072** | 43.108 | 43.348 | 71.786 | 5675.747 |
| `prefix_scan` | **23.829** | 23.907 | 24.161 | 70.081 | 4077.540 |
| `binary_search` | 41.703 | **40.404** | 43.218 | 111.114 | 6381.472 |
| `sort_window` | **28.562** | 28.712 | 28.892 | 198.293 | 11999.015 |
| `bloom_filter` | **18.520** | 19.847 | 20.324 | 2891.341 | 7328.888 |
| `hash_join` | 29.210 | **28.795** | 31.566 | 3397.412 | 7736.151 |
| `sieve` | 26.989 | **26.413** | 26.887 | 75.439 | 3045.727 |
| `fib` | **27.280** | 32.026 | 32.190 | 136.381 | 1105.637 |
| `collatz` | 14.223 | **14.069** | 14.431 | 55.057 | 689.840 |
| `matmul` | 35.740 | **35.348** | 35.755 | 73.833 | 4045.113 |
| `json_parse` | **10.332** | 13.142 | 18.540 | 39.069 | 36.118 |
| `nbody` | **26.420** | 42.046 | 27.657 | 104.636 | 2960.452 |
| `chacha20` | **9.727** | 44.786 | 36.004 | n/a | n/a |
| `poly1305` | **13.401** | 33.827 | 23.286 | n/a | n/a |
| `blake2b` | **46.063** | 66.876 | 71.529 | n/a | n/a |
| `sha512` | 49.856 | **49.842** | 51.938 | n/a | n/a |
| `x25519` | **33.737** | 51.248 | 51.875 | n/a | n/a |

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
| _(floor: empty program)_ | _6.572_ | _119.918_ | _**126.490**_ | _70.746_ | _81.609_ | _66.211_ |
| `lcg` | 6.772 | 130.193 | **136.965** | 64.265 | 92.093 | 72.891 |
| `packet_classifier` | 6.774 | 132.368 | **139.142** | 64.810 | 93.752 | 73.557 |
| `ring_write` | 16.874 | 138.147 | **155.021** | 74.889 | 95.876 | 76.556 |
| `histogram_bins` | 17.163 | 141.047 | **158.210** | 78.157 | 141.718 | 84.721 |
| `prefix_scan` | 16.632 | 134.599 | **151.231** | 74.748 | 100.098 | 78.293 |
| `binary_search` | 16.646 | 133.605 | **150.251** | 73.839 | 95.262 | 80.116 |
| `sort_window` | 16.867 | 135.891 | **152.758** | 74.275 | 105.743 | 86.260 |
| `bloom_filter` | 17.321 | 137.402 | **154.723** | 75.418 | 103.639 | 80.177 |
| `hash_join` | 23.073 | 275.696 | **298.769** | 84.127 | 221.767 | 127.712 |
| `sieve` | 17.044 | 139.382 | **156.426** | 78.048 | 110.567 | 88.908 |
| `fib` | 7.094 | 132.065 | **139.159** | 65.700 | 93.480 | 74.117 |
| `collatz` | 7.045 | 133.007 | **140.052** | 64.948 | 93.824 | 73.964 |
| `matmul` | 17.212 | 135.958 | **153.170** | 75.591 | 109.245 | 95.786 |
| `json_parse` | 50.166 | 461.054 | **511.220** | 110.913 | 162.660 | 178.749 |
| `nbody` | 18.932 | 140.237 | **159.169** | 76.994 | 129.687 | 111.549 |
| `chacha20` | 58.920 | 760.457 | **819.377** | 118.438 | 144.719 | 126.804 |
| `poly1305` | 46.232 | 513.508 | **559.740** | 104.981 | 151.466 | 137.630 |
| `blake2b` | 39.266 | 340.998 | **380.264** | 98.867 | 149.727 | 134.729 |
| `sha512` | 39.876 | 464.784 | **504.660** | 100.810 | 144.582 | 121.698 |
| `x25519` | 53.955 | 1552.587 | **1606.542** | 114.975 | 1258.394 | 515.953 |

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
