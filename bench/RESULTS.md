# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-09T09:51:03Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `8e7a6c38e276d8ba0b2895bf0c7dfeccc0efec8f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42595780537 |
| NURL | `v0.90.0-9-g8e7a6c38` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.2 |
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
| _(floor: empty program)_ | _3.489_ | _3.342_ | _3.600_ | _28.101_ | _15.115_ |
| `lcg` | 41.174 | **40.951** | 41.204 | 1809.242 | 4874.098 |
| `packet_classifier` | 58.721 | **58.567** | 58.769 | 168.072 | 4001.680 |
| `ring_write` | 44.616 | **44.528** | 44.892 | 72.323 | 6235.454 |
| `histogram_bins` | **41.706** | 42.908 | 42.958 | 71.264 | 5551.904 |
| `prefix_scan` | 23.776 | **23.759** | 24.001 | 68.624 | 4046.400 |
| `binary_search` | 41.788 | **41.771** | 42.993 | 110.373 | 6146.325 |
| `sort_window` | 28.810 | **28.767** | 28.934 | 198.713 | 12896.290 |
| `bloom_filter` | **17.829** | 19.638 | 20.681 | 2793.618 | 7307.213 |
| `hash_join` | **28.580** | 28.581 | 31.549 | 3363.691 | 7617.376 |
| `sieve` | 27.097 | 30.334 | **26.952** | 76.043 | 3148.019 |
| `fib` | 32.306 | **32.130** | 32.501 | 138.570 | 1107.492 |
| `collatz` | 14.610 | **14.401** | 14.537 | 54.173 | 684.461 |
| `matmul` | 35.808 | **35.459** | 35.652 | 74.055 | 2948.932 |
| `json_parse` | **8.123** | 13.326 | 18.443 | 41.829 | 36.201 |
| `nbody` | **26.084** | 48.589 | 27.199 | 102.052 | 2951.624 |
| `chacha20` | **9.475** | 40.653 | 35.726 | n/a | n/a |
| `poly1305` | **13.289** | 22.824 | 22.992 | n/a | n/a |
| `blake2b` | **45.956** | 66.815 | 71.040 | n/a | n/a |
| `sha512` | 48.984 | **48.838** | 51.283 | n/a | n/a |
| `x25519` | **34.790** | 51.017 | 51.625 | n/a | n/a |

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
| _(floor: empty program)_ | _7.014_ | _72.613_ | _**79.627**_ | _31.149_ | _40.259_ | _64.520_ |
| `lcg` | 6.987 | 76.979 | **83.966** | 31.307 | 47.830 | 72.011 |
| `packet_classifier` | 7.111 | 78.260 | **85.371** | 31.702 | 48.866 | 72.924 |
| `ring_write` | 15.707 | 80.695 | **96.402** | 40.460 | 48.900 | 73.799 |
| `histogram_bins` | 16.245 | 102.658 | **118.903** | 42.673 | 73.889 | 87.282 |
| `prefix_scan` | 15.991 | 81.163 | **97.154** | 40.512 | 52.606 | 77.867 |
| `binary_search` | 16.038 | 79.433 | **95.471** | 40.341 | 50.439 | 80.275 |
| `sort_window` | 15.758 | 80.640 | **96.398** | 39.884 | 56.787 | 82.892 |
| `bloom_filter` | 16.420 | 81.793 | **98.213** | 40.818 | 55.461 | 80.177 |
| `hash_join` | 20.450 | 147.683 | **168.133** | 45.340 | 120.091 | 129.204 |
| `sieve` | 16.242 | 82.276 | **98.518** | 41.290 | 57.611 | 87.191 |
| `fib` | 7.339 | 79.674 | **87.013** | 32.673 | 49.573 | 73.807 |
| `collatz` | 7.292 | 79.132 | **86.424** | 31.824 | 48.835 | 74.299 |
| `matmul` | 16.246 | 81.689 | **97.935** | 40.993 | 59.792 | 96.410 |
| `json_parse` | 46.523 | 201.735 | **248.258** | 72.193 | 91.294 | 178.492 |
| `nbody` | 17.694 | 85.959 | **103.653** | 42.047 | 72.331 | 110.033 |
| `chacha20` | 66.350 | 425.305 | **491.655** | 91.267 | 79.718 | 121.707 |
| `poly1305` | 54.922 | 250.698 | **305.620** | 79.214 | 83.525 | 136.718 |
| `blake2b` | 36.210 | 208.821 | **245.031** | 60.852 | 79.426 | 131.678 |
| `sha512` | 35.093 | 297.961 | **333.054** | 60.001 | 79.612 | 117.603 |
| `x25519` | 50.844 | 1055.763 | **1106.607** | 78.159 | 945.495 | 511.042 |

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
