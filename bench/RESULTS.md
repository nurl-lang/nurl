# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T02:24:42Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a35dd39f8de35f4060b312a21fe78e3bcac96be4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41159388489 |
| NURL | `v0.81.0-38-ga35dd39f` |
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
| _(floor: empty program)_ | _3.439_ | _3.321_ | _3.562_ | _28.506_ | _15.492_ |
| `lcg` | 41.320 | **41.293** | 41.523 | 1795.718 | 4886.987 |
| `packet_classifier` | 59.602 | 59.043 | **59.030** | 167.322 | 4131.759 |
| `ring_write` | 44.517 | **44.427** | 44.757 | 71.388 | 6159.832 |
| `histogram_bins` | **41.825** | 43.193 | 43.289 | 72.356 | 5869.906 |
| `prefix_scan` | 24.278 | **24.225** | 24.389 | 68.889 | 4314.645 |
| `binary_search` | 41.575 | **40.113** | 42.973 | 110.775 | 5765.878 |
| `sort_window` | 28.929 | **28.738** | 28.851 | 200.325 | 12124.687 |
| `bloom_filter` | **18.482** | 19.731 | 20.192 | 2866.470 | 7564.293 |
| `hash_join` | 28.822 | **28.384** | 31.107 | 3376.724 | 7659.733 |
| `sieve` | 24.839 | **24.617** | 26.855 | 76.516 | 3171.688 |
| `fib` | **27.668** | 32.272 | 32.465 | 135.777 | 1108.896 |
| `collatz` | **14.495** | 14.500 | 14.608 | 55.577 | 689.325 |
| `matmul` | 35.594 | **35.358** | 36.086 | 76.506 | 2983.986 |
| `json_parse` | **10.174** | 12.869 | 18.399 | 39.079 | 36.271 |
| `nbody` | **26.247** | 41.980 | 27.457 | 102.441 | 2952.149 |
| `chacha20` | **9.433** | 43.933 | 36.101 | n/a | n/a |
| `poly1305` | **13.303** | 33.981 | 23.052 | n/a | n/a |
| `blake2b` | **45.942** | 66.536 | 71.553 | n/a | n/a |
| `sha512` | **49.252** | 49.459 | 51.489 | n/a | n/a |
| `x25519` | **33.514** | 50.979 | 51.500 | n/a | n/a |

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
| _(floor: empty program)_ | _6.804_ | _122.348_ | _**129.152**_ | _67.397_ | _83.142_ | _66.224_ |
| `lcg` | 6.903 | 133.942 | **140.845** | 66.132 | 91.549 | 78.776 |
| `packet_classifier` | 6.967 | 132.812 | **139.779** | 65.686 | 93.881 | 73.780 |
| `ring_write` | 17.209 | 135.276 | **152.485** | 76.807 | 94.900 | 74.325 |
| `histogram_bins` | 17.640 | 134.503 | **152.143** | 75.183 | 137.313 | 85.993 |
| `prefix_scan` | 17.486 | 135.002 | **152.488** | 76.293 | 101.227 | 80.884 |
| `binary_search` | 17.635 | 131.959 | **149.594** | 74.083 | 93.691 | 77.877 |
| `sort_window` | 18.181 | 140.672 | **158.853** | 78.219 | 107.624 | 86.586 |
| `bloom_filter` | 18.147 | 135.943 | **154.090** | 75.163 | 103.614 | 80.177 |
| `hash_join` | 21.833 | 270.331 | **292.164** | 78.698 | 217.791 | 124.752 |
| `sieve` | 17.680 | 134.765 | **152.445** | 76.109 | 106.291 | 90.196 |
| `fib` | 7.038 | 133.013 | **140.051** | 65.793 | 92.709 | 74.767 |
| `collatz` | 7.212 | 137.206 | **144.418** | 65.845 | 95.866 | 75.901 |
| `matmul` | 18.291 | 135.821 | **154.112** | 76.372 | 108.710 | 97.120 |
| `json_parse` | 51.851 | 456.835 | **508.686** | 110.485 | 158.869 | 181.056 |
| `nbody` | 19.618 | 138.340 | **157.958** | 76.160 | 126.858 | 111.828 |
| `chacha20` | 58.745 | 786.448 | **845.193** | 116.325 | 146.736 | 127.628 |
| `poly1305` | 46.440 | 515.961 | **562.401** | 107.065 | 151.312 | 141.522 |
| `blake2b` | 40.920 | 338.825 | **379.745** | 98.956 | 145.496 | 134.180 |
| `sha512` | 40.543 | 456.774 | **497.317** | 98.740 | 140.219 | 118.484 |
| `x25519` | 55.677 | 1552.948 | **1608.625** | 114.488 | 1244.507 | 512.010 |

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
