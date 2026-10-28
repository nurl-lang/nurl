# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T19:01:20Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `3556f8cfe8ae7138446630a5df7702ea01e76006` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40749532312 |
| NURL | `v0.80.0-9-g3556f8cf` |
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
| _(floor: empty program)_ | _1.612_ | _1.552_ | _1.808_ | _24.353_ | _17.944_ |
| `lcg` | 39.447 | **39.445** | 39.699 | 1820.529 | 5178.216 |
| `packet_classifier` | 56.647 | **56.622** | 56.826 | 165.054 | 4305.414 |
| `ring_write` | **42.602** | 42.621 | 42.664 | 70.744 | 6567.637 |
| `histogram_bins` | **39.768** | 40.862 | 41.050 | 67.969 | 6044.860 |
| `prefix_scan` | 21.813 | **21.776** | 21.981 | 67.369 | 4426.596 |
| `binary_search` | 39.947 | **38.448** | 41.069 | 109.896 | 6246.657 |
| `sort_window` | **26.886** | 26.968 | 27.160 | 201.480 | 11198.163 |
| `bloom_filter` | **16.883** | 18.068 | 18.568 | 2910.638 | 7529.186 |
| `hash_join` | **27.537** | 28.422 | 29.606 | 3502.159 | 8259.950 |
| `sieve` | 27.818 | 23.856 | **23.715** | 74.840 | 3335.624 |
| `fib` | **25.459** | 30.266 | 30.450 | 134.246 | 1361.860 |
| `collatz` | 12.597 | **12.513** | 12.712 | 54.450 | 741.451 |
| `matmul` | **34.072** | 34.148 | 34.162 | 81.161 | 3324.984 |
| `json_parse` | 8.961 | **8.917** | 12.166 | 38.496 | 40.451 |
| `nbody` | **25.525** | 40.122 | 25.654 | 106.308 | 3133.734 |
| `chacha20` | **7.530** | 42.400 | 34.023 | n/a | n/a |
| `poly1305` | **12.111** | 32.191 | 21.449 | n/a | n/a |
| `blake2b` | **43.971** | 65.396 | 69.558 | n/a | n/a |
| `sha512` | **47.713** | 50.896 | 49.921 | n/a | n/a |
| `x25519` | **31.752** | 48.996 | 49.693 | n/a | n/a |

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
| _(floor: empty program)_ | _4.753_ | _125.643_ | _**130.396**_ | _67.492_ | _89.235_ | _65.796_ |
| `lcg` | 4.887 | 135.199 | **140.086** | 67.308 | 96.795 | 74.523 |
| `packet_classifier` | 4.970 | 135.791 | **140.761** | 66.655 | 98.147 | 76.067 |
| `ring_write` | 15.953 | 141.031 | **156.984** | 78.281 | 100.199 | 77.034 |
| `histogram_bins` | 15.621 | 137.460 | **153.081** | 77.772 | 115.947 | 82.688 |
| `prefix_scan` | 15.679 | 138.195 | **153.874** | 76.297 | 103.511 | 79.255 |
| `binary_search` | 15.908 | 138.155 | **154.063** | 77.031 | 103.636 | 81.380 |
| `sort_window` | 16.194 | 140.714 | **156.908** | 77.739 | 113.242 | 86.965 |
| `bloom_filter` | 16.725 | 143.122 | **159.847** | 77.811 | 110.013 | 81.502 |
| `hash_join` | 20.572 | 274.157 | **294.729** | 83.881 | 230.450 | 130.521 |
| `sieve` | 16.530 | 143.605 | **160.135** | 82.737 | 115.858 | 92.242 |
| `fib` | 5.288 | 143.365 | **148.653** | 71.406 | 102.844 | 79.476 |
| `collatz` | 5.358 | 144.428 | **149.786** | 71.358 | 107.127 | 81.100 |
| `matmul` | 17.899 | 147.131 | **165.030** | 83.950 | 121.229 | 103.553 |
| `json_parse` | 52.082 | 513.147 | **565.229** | 119.166 | 180.948 | 188.595 |
| `nbody` | 19.525 | 154.725 | **174.250** | 86.279 | 146.447 | 120.251 |
| `chacha20` | 60.131 | 780.069 | **840.200** | 124.666 | 155.157 | 132.990 |
| `poly1305` | 45.750 | 531.297 | **577.047** | 113.727 | 155.017 | 144.154 |
| `blake2b` | 41.623 | 397.112 | **438.735** | 108.092 | 163.851 | 140.280 |
| `sha512` | 40.824 | 490.672 | **531.496** | 106.261 | 151.716 | 125.463 |
| `x25519` | 54.385 | 1217.265 | **1271.650** | 120.058 | 1259.137 | 522.023 |

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
