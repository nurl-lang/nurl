# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-04T01:27:58Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `6500a696edc94cdfac23dd3ddf3df7e20d1e6812` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/33825546263 |
| NURL | `v0.59.0-10-g6500a696` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.98.1 (48a229cea 2026-09-01) |
| Node | v22.23.2 |
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

## 1. Run time (median wall clock, ms — lower is better)

Whole-process wall clock, start-up included. Every implementation of a
row prints the same line (section 3), so these are five timings of the
same computation. **Bold** is the fastest cell in the row.

| Benchmark | NURL | C | Rust | Node | Python |
|---|---:|---:|---:|---:|---:|
| _(floor: empty program)_ | _1.538_ | _1.532_ | _1.743_ | _25.056_ | _18.533_ |
| `lcg` | **44.044** | 44.122 | 44.333 | 1851.337 | 5414.933 |
| `packet_classifier` | **63.585** | 63.587 | 63.773 | 159.157 | 5249.113 |
| `ring_write` | 47.684 | **47.641** | 47.836 | 74.688 | 7189.028 |
| `histogram_bins` | 44.702 | **44.655** | 44.860 | 75.948 | 6540.594 |
| `prefix_scan` | **24.490** | 24.557 | 24.720 | 71.938 | 4822.584 |
| `binary_search` | 41.499 | **35.785** | 36.737 | 111.828 | 6647.155 |
| `sort_window` | **29.999** | 30.008 | 30.287 | 165.953 | 15003.746 |
| `bloom_filter` | 19.783 | **18.747** | 20.736 | 2797.887 | 7765.515 |
| `hash_join` | **27.765** | 28.820 | 30.400 | 3469.646 | 8289.428 |
| `sieve` | 20.689 | **20.276** | 20.453 | 72.562 | 3544.247 |
| `fib` | **28.004** | 33.367 | 28.299 | 143.796 | 1274.093 |
| `collatz` | **13.789** | 13.870 | 14.008 | 54.683 | 750.322 |
| `matmul` | 47.000 | **46.517** | 46.711 | 88.054 | 3412.947 |
| `json_parse` | 9.044 | **8.958** | 12.258 | 42.121 | 42.163 |
| `nbody` | 26.927 | 45.120 | **26.419** | 99.286 | 3289.494 |

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
| _(floor: empty program)_ | _2.962_ | _106.968_ | _**109.930**_ | _65.634_ | _90.021_ | _57.751_ |
| `lcg` | 3.203 | 117.453 | **120.656** | 65.954 | 97.073 | 63.315 |
| `packet_classifier` | 3.250 | 118.256 | **121.506** | 64.979 | 110.601 | 65.277 |
| `ring_write` | 3.348 | 118.093 | **121.441** | 65.927 | 102.207 | 65.638 |
| `histogram_bins` | 3.422 | 126.142 | **129.564** | 65.643 | 116.033 | 73.265 |
| `prefix_scan` | 3.479 | 119.949 | **123.428** | 66.602 | 106.759 | 68.527 |
| `binary_search` | 3.629 | 118.970 | **122.599** | 66.118 | 102.287 | 70.275 |
| `sort_window` | 3.654 | 120.542 | **124.196** | 65.995 | 110.646 | 74.530 |
| `bloom_filter` | 3.975 | 121.206 | **125.181** | 66.604 | 108.635 | 70.523 |
| `hash_join` | 6.683 | 261.248 | **267.931** | 70.472 | 218.409 | 120.582 |
| `sieve` | 3.518 | 118.791 | **122.309** | 66.513 | 111.536 | 74.747 |
| `fib` | 3.210 | 119.587 | **122.797** | 67.417 | 100.584 | 64.597 |
| `collatz` | 3.391 | 122.600 | **125.991** | 68.132 | 101.721 | 67.085 |
| `matmul` | 3.798 | 119.663 | **123.461** | 66.904 | 113.933 | 89.335 |
| `json_parse` | 57.347 | 449.492 | **506.839** | 123.491 | 166.144 | 177.386 |
| `nbody` | 5.155 | 138.947 | **144.102** | 69.313 | 135.227 | 100.572 |

## 3. Correctness gate

Each row is timed only when all five implementations print the same
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

## 4. Reading the numbers

* A cell near the floor row is mostly process start-up, dynamic linking
  and page faults rather than the benchmark. The rows worth comparing are
  the ones in the tens of milliseconds and up.
* All three compiled back ends are LLVM-based and all three are allowed to
  be clever: LLVM will fold an affine recurrence or unroll a loop by a
  different factor in each language. A cell measures optimised throughput
  of the same algorithm, not the source-level iteration count.
* Nine of the fifteen benchmarks are defined over 64-bit unsigned integers.
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
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
