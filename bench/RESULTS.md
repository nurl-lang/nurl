# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-23T14:20:38Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `955ab9fca1f6af625aadf005537a0590aa0430ef` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39968025636 |
| NURL | `v0.77.2-3-g955ab9fc` |
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
| _(floor: empty program)_ | _1.226_ | _1.203_ | _1.339_ | _18.916_ | _13.072_ |
| `lcg` | 30.042 | **29.926** | 30.064 | 1128.793 | 3054.510 |
| `packet_classifier` | **43.354** | 43.492 | 43.671 | 135.939 | 2766.675 |
| `ring_write` | **30.065** | 30.226 | 30.514 | 52.380 | 3673.244 |
| `histogram_bins` | 30.243 | **30.022** | 30.070 | 51.420 | 3469.566 |
| `prefix_scan` | 16.661 | **16.483** | 16.720 | 50.477 | 2715.837 |
| `binary_search` | **14.855** | 14.966 | 15.849 | 70.901 | 3765.052 |
| `sort_window` | 21.795 | **20.856** | 21.486 | 138.153 | 6449.974 |
| `bloom_filter` | **9.087** | 9.131 | 9.280 | 1644.598 | 4444.654 |
| `hash_join` | **17.158** | 17.798 | 18.954 | 1971.000 | 4699.010 |
| `sieve` | 12.456 | **12.319** | 12.441 | 47.971 | 2000.926 |
| `fib` | 19.623 | **19.545** | 19.660 | 80.992 | 685.538 |
| `collatz` | **9.645** | 9.813 | 10.269 | 39.465 | 421.729 |
| `matmul` | **20.850** | 21.288 | 21.437 | 56.938 | 1974.350 |
| `json_parse` | **5.235** | 6.149 | 7.364 | 28.473 | 26.818 |
| `nbody` | **17.141** | 25.497 | 17.820 | 63.509 | 1539.224 |
| `chacha20` | **7.032** | 20.405 | 19.913 | n/a | n/a |
| `poly1305` | **15.972** | 27.764 | 16.044 | n/a | n/a |
| `blake2b` | **26.860** | 43.359 | 48.414 | n/a | n/a |
| `sha512` | **30.361** | 33.524 | 32.605 | n/a | n/a |
| `x25519` | **30.164** | 33.012 | 32.757 | n/a | n/a |

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
| _(floor: empty program)_ | _3.675_ | _93.492_ | _**97.167**_ | _51.929_ | _70.087_ | _47.165_ |
| `lcg` | 3.660 | 100.941 | **104.601** | 52.640 | 96.608 | 52.655 |
| `packet_classifier` | 3.794 | 100.990 | **104.784** | 51.150 | 76.557 | 49.488 |
| `ring_write` | 10.075 | 104.696 | **114.771** | 58.708 | 80.353 | 52.612 |
| `histogram_bins` | 9.392 | 99.094 | **108.486** | 55.846 | 86.291 | 54.823 |
| `prefix_scan` | 9.765 | 101.521 | **111.286** | 58.731 | 82.077 | 52.660 |
| `binary_search` | 9.651 | 99.287 | **108.938** | 55.722 | 81.220 | 55.544 |
| `sort_window` | 9.815 | 98.909 | **108.724** | 55.144 | 81.606 | 55.668 |
| `bloom_filter` | 10.105 | 102.438 | **112.543** | 55.151 | 85.076 | 55.352 |
| `hash_join` | 12.299 | 183.640 | **195.939** | 58.958 | 150.922 | 101.473 |
| `sieve` | 9.672 | 98.343 | **108.015** | 56.583 | 82.621 | 57.888 |
| `fib` | 3.752 | 97.795 | **101.547** | 51.631 | 77.266 | 50.115 |
| `collatz` | 3.911 | 100.336 | **104.247** | 52.180 | 77.857 | 49.433 |
| `matmul` | 10.823 | 100.802 | **111.625** | 57.989 | 87.881 | 65.111 |
| `json_parse` | 31.081 | 329.484 | **360.565** | 79.671 | 120.671 | 122.811 |
| `nbody` | 11.725 | 110.891 | **122.616** | 60.759 | 100.765 | 83.317 |
| `chacha20` | 29.898 | 516.633 | **546.531** | 78.063 | 108.068 | 83.684 |
| `poly1305` | 20.939 | 198.169 | **219.108** | 68.448 | 109.210 | 93.189 |
| `blake2b` | 25.605 | 254.540 | **280.145** | 73.319 | 109.127 | 88.771 |
| `sha512` | 22.798 | 302.255 | **325.053** | 68.309 | 100.921 | 77.997 |
| `x25519` | 22.365 | 512.345 | **534.710** | 67.806 | 747.502 | 332.504 |

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
