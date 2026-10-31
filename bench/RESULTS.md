# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T03:07:54Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `e135cff2966ae60116912a2f1c504c2788a2dcb4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41162559949 |
| NURL | `v0.81.0-42-ge135cff2` |
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
| _(floor: empty program)_ | _3.560_ | _3.400_ | _3.738_ | _27.852_ | _15.524_ |
| `lcg` | 41.490 | **41.365** | 41.526 | 1797.289 | 5104.438 |
| `packet_classifier` | 58.798 | **58.778** | 58.836 | 167.273 | 4224.966 |
| `ring_write` | **44.732** | 45.434 | 45.612 | 76.705 | 6114.897 |
| `histogram_bins` | **42.031** | 43.050 | 43.260 | 72.543 | 5705.890 |
| `prefix_scan` | **24.013** | 24.142 | 24.103 | 69.330 | 4163.365 |
| `binary_search` | 41.902 | **40.400** | 43.344 | 111.388 | 6306.029 |
| `sort_window` | **29.065** | 29.135 | 29.170 | 198.304 | 12109.338 |
| `bloom_filter` | **18.860** | 19.968 | 20.555 | 2880.885 | 7011.572 |
| `hash_join` | 29.037 | **28.786** | 31.505 | 3395.508 | 7774.158 |
| `sieve` | 25.318 | **24.578** | 24.784 | 72.693 | 3152.883 |
| `fib` | **27.277** | 32.240 | 32.308 | 136.251 | 1109.539 |
| `collatz` | 14.427 | **14.167** | 14.363 | 53.777 | 688.906 |
| `matmul` | 35.615 | **35.552** | 35.749 | 74.325 | 3105.271 |
| `json_parse` | **10.350** | 12.962 | 18.406 | 38.489 | 36.603 |
| `nbody` | **26.181** | 42.113 | 27.618 | 102.810 | 3073.048 |
| `chacha20` | **9.188** | 44.439 | 35.925 | n/a | n/a |
| `poly1305` | **13.512** | 33.856 | 23.115 | n/a | n/a |
| `blake2b` | **46.215** | 66.860 | 71.382 | n/a | n/a |
| `sha512` | **49.684** | 49.814 | 51.766 | n/a | n/a |
| `x25519` | **34.011** | 51.507 | 51.666 | n/a | n/a |

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
| _(floor: empty program)_ | _6.925_ | _119.800_ | _**126.725**_ | _65.896_ | _85.722_ | _67.814_ |
| `lcg` | 6.907 | 132.665 | **139.572** | 66.255 | 92.980 | 73.439 |
| `packet_classifier` | 6.910 | 133.670 | **140.580** | 66.835 | 96.050 | 74.014 |
| `ring_write` | 17.444 | 135.763 | **153.207** | 77.285 | 95.389 | 75.728 |
| `histogram_bins` | 18.251 | 138.766 | **157.017** | 78.936 | 142.360 | 84.281 |
| `prefix_scan` | 17.496 | 137.084 | **154.580** | 77.081 | 102.400 | 79.677 |
| `binary_search` | 17.879 | 137.109 | **154.988** | 78.265 | 97.499 | 79.548 |
| `sort_window` | 18.017 | 141.577 | **159.594** | 78.417 | 109.434 | 86.498 |
| `bloom_filter` | 18.628 | 141.953 | **160.581** | 77.686 | 118.834 | 80.802 |
| `hash_join` | 21.930 | 272.546 | **294.476** | 81.953 | 225.133 | 127.424 |
| `sieve` | 17.403 | 135.330 | **152.733** | 75.886 | 108.352 | 89.385 |
| `fib` | 7.180 | 136.263 | **143.443** | 66.766 | 96.438 | 75.548 |
| `collatz` | 7.029 | 134.631 | **141.660** | 64.602 | 98.232 | 75.421 |
| `matmul` | 17.935 | 134.086 | **152.021** | 75.344 | 109.151 | 98.633 |
| `json_parse` | 52.218 | 460.090 | **512.308** | 113.208 | 163.055 | 176.197 |
| `nbody` | 19.741 | 140.179 | **159.920** | 77.617 | 130.382 | 111.044 |
| `chacha20` | 58.429 | 786.195 | **844.624** | 117.995 | 144.728 | 124.127 |
| `poly1305` | 46.242 | 516.902 | **563.144** | 105.050 | 149.585 | 139.426 |
| `blake2b` | 40.847 | 339.190 | **380.037** | 100.042 | 148.817 | 132.452 |
| `sha512` | 40.988 | 458.829 | **499.817** | 99.988 | 141.708 | 118.338 |
| `x25519` | 56.087 | 1554.203 | **1610.290** | 114.859 | 1251.849 | 515.721 |

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
