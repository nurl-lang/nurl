# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-09-13T12:03:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `2ea2ac0b925755b85ab357f04a16b31ce4c3f178` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/34755812249 |
| NURL | `v0.64.0-2-g2ea2ac0b` |
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
| _(floor: empty program)_ | _1.494_ | _1.445_ | _1.620_ | _23.549_ | _17.660_ |
| `lcg` | 39.361 | **39.141** | 39.385 | 2076.392 | 5158.020 |
| `packet_classifier` | **56.354** | 56.381 | 56.492 | 162.824 | 4346.148 |
| `ring_write` | 42.331 | **42.307** | 42.442 | 67.462 | 6369.343 |
| `histogram_bins` | **39.540** | 40.695 | 39.745 | 67.203 | 6224.446 |
| `prefix_scan` | **21.876** | 21.939 | 21.935 | 67.885 | 4598.453 |
| `binary_search` | 39.615 | 38.277 | **36.950** | 106.694 | 6096.163 |
| `sort_window` | 26.601 | **26.573** | 26.910 | 197.871 | 11469.531 |
| `bloom_filter` | **16.713** | 17.925 | 18.375 | 2870.654 | 7796.437 |
| `hash_join` | **26.874** | 27.759 | 29.312 | 3446.600 | 8394.924 |
| `sieve` | 18.726 | **18.095** | 18.444 | 65.861 | 3224.958 |
| `fib` | **25.224** | 29.779 | 25.362 | 131.739 | 1367.300 |
| `collatz` | **12.223** | 12.278 | 12.461 | 51.681 | 717.786 |
| `matmul` | 33.543 | **33.464** | 33.747 | 76.659 | 3205.615 |
| `json_parse` | 9.834 | **8.582** | 11.670 | 36.964 | 40.347 |
| `nbody` | 25.265 | 39.856 | **24.134** | 102.826 | 3100.800 |

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
| _(floor: empty program)_ | _3.282_ | _100.773_ | _**104.055**_ | _62.698_ | _81.774_ | _62.931_ |
| `lcg` | 3.457 | 108.873 | **112.330** | 59.947 | 91.053 | 69.832 |
| `packet_classifier` | 3.569 | 108.495 | **112.064** | 59.583 | 90.063 | 67.241 |
| `ring_write` | 3.783 | 110.752 | **114.535** | 61.344 | 93.571 | 69.925 |
| `histogram_bins` | 3.888 | 118.907 | **122.795** | 60.754 | 109.722 | 79.284 |
| `prefix_scan` | 3.955 | 111.351 | **115.306** | 61.193 | 98.053 | 73.654 |
| `binary_search` | 4.183 | 111.944 | **116.127** | 60.531 | 97.211 | 76.633 |
| `sort_window` | 4.364 | 113.249 | **117.613** | 61.369 | 104.940 | 81.306 |
| `bloom_filter` | 4.820 | 113.796 | **118.616** | 62.111 | 102.911 | 76.351 |
| `hash_join` | 9.521 | 262.959 | **272.480** | 67.381 | 221.632 | 126.975 |
| `sieve` | 3.985 | 111.586 | **115.571** | 62.088 | 103.760 | 80.409 |
| `fib` | 3.559 | 110.340 | **113.899** | 61.471 | 90.553 | 68.145 |
| `collatz` | 3.823 | 110.118 | **113.941** | 60.078 | 91.374 | 71.378 |
| `matmul` | 4.445 | 109.897 | **114.342** | 60.573 | 105.947 | 95.059 |
| `json_parse` | 106.647 | 473.633 | **580.280** | 164.134 | 160.274 | 181.188 |
| `nbody` | 6.583 | 129.460 | **136.043** | 63.742 | 126.983 | 103.356 |

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
