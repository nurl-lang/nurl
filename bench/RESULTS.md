# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T12:53:09Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `cbded345254c47b84ebf4c6bbfbd83d19647b40c` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40876099928 |
| NURL | `v0.80.0-59-gcbded345` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v22.23.4 |
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
| _(floor: empty program)_ | _1.565_ | _1.529_ | _1.755_ | _23.220_ | _17.866_ |
| `lcg` | **39.127** | 39.208 | 39.342 | 1816.303 | 5084.377 |
| `packet_classifier` | **56.251** | 56.583 | 56.852 | 163.919 | 4321.746 |
| `ring_write` | **42.298** | 42.301 | 42.510 | 68.008 | 6413.363 |
| `histogram_bins` | **39.545** | 40.681 | 40.973 | 67.665 | 6026.238 |
| `prefix_scan` | 21.802 | **21.785** | 22.045 | 66.929 | 4734.429 |
| `binary_search` | 39.804 | **38.399** | 41.063 | 108.413 | 6299.587 |
| `sort_window` | **26.693** | 26.752 | 26.970 | 199.211 | 12186.489 |
| `bloom_filter` | **16.734** | 17.935 | 18.453 | 2893.905 | 7788.873 |
| `hash_join` | **26.967** | 27.975 | 29.283 | 3471.524 | 8211.392 |
| `sieve` | 22.850 | **21.894** | 22.208 | 70.891 | 3224.943 |
| `fib` | **25.153** | 29.925 | 30.035 | 133.523 | 1358.758 |
| `collatz` | 12.327 | **12.264** | 12.495 | 49.433 | 750.096 |
| `matmul` | **33.703** | 33.756 | 34.092 | 79.901 | 3122.150 |
| `json_parse` | **8.512** | 8.713 | 11.855 | 36.393 | 38.833 |
| `nbody` | **25.411** | 40.044 | 25.547 | 103.661 | 3206.957 |
| `chacha20` | **7.491** | 40.351 | 33.700 | n/a | n/a |
| `poly1305` | **11.867** | 31.914 | 21.233 | n/a | n/a |
| `blake2b` | **44.338** | 65.389 | 69.358 | n/a | n/a |
| `sha512` | **47.655** | 50.756 | 49.640 | n/a | n/a |
| `x25519` | **31.594** | 48.829 | 49.824 | n/a | n/a |

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
| _(floor: empty program)_ | _4.673_ | _117.521_ | _**122.194**_ | _63.502_ | _84.078_ | _63.329_ |
| `lcg` | 4.844 | 129.895 | **134.739** | 63.984 | 91.751 | 69.378 |
| `packet_classifier` | 5.112 | 136.947 | **142.059** | 67.997 | 97.932 | 73.100 |
| `ring_write` | 16.194 | 138.501 | **154.695** | 77.337 | 100.465 | 77.390 |
| `histogram_bins` | 15.635 | 132.795 | **148.430** | 72.849 | 112.423 | 81.678 |
| `prefix_scan` | 15.763 | 133.515 | **149.278** | 73.678 | 101.258 | 77.057 |
| `binary_search` | 15.758 | 132.697 | **148.455** | 74.224 | 97.251 | 77.235 |
| `sort_window` | 16.093 | 135.446 | **151.539** | 74.906 | 106.518 | 83.016 |
| `bloom_filter` | 16.543 | 135.436 | **151.979** | 74.137 | 105.028 | 78.348 |
| `hash_join` | 20.144 | 265.141 | **285.285** | 77.716 | 220.224 | 123.410 |
| `sieve` | 15.725 | 131.166 | **146.891** | 73.326 | 106.388 | 86.208 |
| `fib` | 4.918 | 130.634 | **135.552** | 64.546 | 93.446 | 72.007 |
| `collatz` | 5.182 | 133.881 | **139.063** | 64.893 | 96.162 | 72.476 |
| `matmul` | 17.547 | 137.242 | **154.789** | 77.623 | 111.585 | 95.053 |
| `json_parse` | 51.398 | 481.209 | **532.607** | 112.729 | 167.761 | 173.345 |
| `nbody` | 18.299 | 137.354 | **155.653** | 75.659 | 130.126 | 109.114 |
| `chacha20` | 59.033 | 769.985 | **829.018** | 120.080 | 146.772 | 123.220 |
| `poly1305` | 44.732 | 513.910 | **558.642** | 103.916 | 144.775 | 135.249 |
| `blake2b` | 39.778 | 378.977 | **418.755** | 101.852 | 154.903 | 137.338 |
| `sha512` | 40.013 | 485.647 | **525.660** | 101.043 | 144.366 | 117.464 |
| `x25519` | 54.034 | 1302.995 | **1357.029** | 114.757 | 1228.549 | 511.681 |

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
