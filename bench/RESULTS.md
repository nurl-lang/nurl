# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T07:10:48Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `03f6efde702fe6710bee106af39f34466030309d` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40647747243 |
| NURL | `v0.79.1-23-g03f6efde` |
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
| _(floor: empty program)_ | _1.447_ | _1.411_ | _1.662_ | _21.638_ | _16.846_ |
| `lcg` | **38.925** | 39.007 | 39.133 | 1896.034 | 5149.804 |
| `packet_classifier` | 56.191 | **56.041** | 56.225 | 160.264 | 4389.594 |
| `ring_write` | 42.175 | **42.146** | 42.274 | 64.746 | 6391.462 |
| `histogram_bins` | **39.569** | 40.538 | 40.800 | 64.914 | 6247.574 |
| `prefix_scan` | **21.714** | 21.726 | 21.953 | 64.220 | 4583.543 |
| `binary_search` | 39.834 | **38.114** | 40.902 | 106.742 | 6115.833 |
| `sort_window` | 26.535 | **26.489** | 26.704 | 198.081 | 12702.232 |
| `bloom_filter` | **16.716** | 17.866 | 18.457 | 2832.784 | 7702.712 |
| `hash_join` | **26.835** | 28.023 | 29.375 | 3428.481 | 8519.910 |
| `sieve` | 20.539 | **18.403** | 20.499 | 68.823 | 3334.589 |
| `fib` | **25.237** | 29.938 | 29.949 | 132.596 | 1395.616 |
| `collatz` | 12.236 | **12.223** | 12.428 | 49.493 | 738.556 |
| `matmul` | **33.718** | 33.796 | 33.947 | 77.023 | 3292.118 |
| `json_parse` | **8.577** | 8.698 | 11.948 | 37.216 | 39.951 |
| `nbody` | **25.346** | 39.725 | 25.612 | 102.751 | 3124.708 |
| `chacha20` | **7.501** | 42.553 | 33.850 | n/a | n/a |
| `poly1305` | **11.776** | 31.958 | 21.296 | n/a | n/a |
| `blake2b` | **43.814** | 65.131 | 69.327 | n/a | n/a |
| `sha512` | **47.609** | 50.829 | 49.710 | n/a | n/a |
| `x25519` | **35.668** | 48.949 | 49.450 | n/a | n/a |

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
| _(floor: empty program)_ | _4.335_ | _112.359_ | _**116.694**_ | _59.896_ | _76.184_ | _51.864_ |
| `lcg` | 4.471 | 123.375 | **127.846** | 60.205 | 86.183 | 57.136 |
| `packet_classifier` | 4.590 | 125.702 | **130.292** | 61.499 | 88.309 | 58.224 |
| `ring_write` | 14.967 | 126.459 | **141.426** | 70.450 | 88.676 | 59.349 |
| `histogram_bins` | 15.170 | 127.939 | **143.109** | 70.422 | 105.975 | 66.597 |
| `prefix_scan` | 15.373 | 129.313 | **144.686** | 71.355 | 95.806 | 61.948 |
| `binary_search` | 15.474 | 128.975 | **144.449** | 71.446 | 92.678 | 63.576 |
| `sort_window` | 15.641 | 130.171 | **145.812** | 70.727 | 100.783 | 68.860 |
| `bloom_filter` | 16.061 | 131.591 | **147.652** | 71.282 | 100.646 | 65.160 |
| `hash_join` | 20.086 | 266.315 | **286.401** | 76.614 | 217.439 | 110.953 |
| `sieve` | 15.881 | 130.202 | **146.083** | 73.398 | 103.277 | 70.602 |
| `fib` | 4.748 | 129.158 | **133.906** | 64.432 | 91.180 | 58.785 |
| `collatz` | 5.010 | 132.591 | **137.601** | 64.016 | 93.255 | 59.809 |
| `matmul` | 17.053 | 133.895 | **150.948** | 76.675 | 108.817 | 80.022 |
| `json_parse` | 51.763 | 499.185 | **550.948** | 112.097 | 163.906 | 159.604 |
| `nbody` | 19.291 | 139.494 | **158.785** | 77.999 | 130.943 | 95.706 |
| `chacha20` | 58.250 | 763.350 | **821.600** | 117.618 | 142.623 | 106.781 |
| `poly1305` | 45.326 | 524.700 | **570.026** | 106.577 | 146.390 | 124.572 |
| `blake2b` | 40.280 | 384.700 | **424.980** | 100.249 | 151.923 | 118.121 |
| `sha512` | 40.442 | 478.939 | **519.381** | 99.736 | 141.128 | 103.686 |
| `x25519` | 51.566 | 1252.288 | **1303.854** | 111.162 | 1229.807 | 498.669 |

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
