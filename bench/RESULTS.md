# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-07T08:48:49Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1019-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16366640 KiB |
| Commit | `11f6a9408eebea225fc5362d7898701db025cef2` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/42356743536 |
| NURL | `v0.90.0-1-g11f6a940` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
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
| _(floor: empty program)_ | _2.885_ | _2.806_ | _2.978_ | _20.409_ | _11.320_ |
| `lcg` | 31.636 | **31.472** | 31.739 | 1163.256 | 2867.946 |
| `packet_classifier` | **44.865** | 44.974 | 45.011 | 137.979 | 2501.945 |
| `ring_write` | 31.997 | **31.706** | 32.401 | 56.706 | 3603.105 |
| `histogram_bins` | 31.805 | **31.640** | 31.951 | 54.635 | 3245.175 |
| `prefix_scan` | 18.238 | **18.141** | 18.258 | 50.034 | 2398.961 |
| `binary_search` | 16.946 | **16.740** | 17.375 | 74.865 | 3846.274 |
| `sort_window` | 22.844 | **22.432** | 22.692 | 140.182 | 8242.454 |
| `bloom_filter` | 10.904 | **10.672** | 10.785 | 1659.374 | 4061.512 |
| `hash_join` | 18.239 | **17.572** | 19.834 | 1955.587 | 4202.111 |
| `sieve` | 16.860 | 16.662 | **16.639** | 51.973 | 1707.036 |
| `fib` | 21.367 | **20.862** | 21.176 | 79.434 | 568.078 |
| `collatz` | 11.186 | **10.954** | 11.132 | 39.039 | 386.109 |
| `matmul` | 22.706 | 22.742 | **22.509** | 53.692 | 1527.252 |
| `json_parse` | **5.367** | 8.572 | 12.079 | 26.709 | 22.791 |
| `nbody` | **17.726** | 26.705 | 18.960 | 60.799 | 1396.956 |
| `chacha20` | **5.042** | 21.533 | 21.198 | n/a | n/a |
| `poly1305` | **8.077** | 28.738 | 17.610 | n/a | n/a |
| `blake2b` | **28.004** | 45.242 | 50.533 | n/a | n/a |
| `sha512` | 31.938 | **31.713** | 34.142 | n/a | n/a |
| `x25519` | **21.154** | 32.056 | 32.868 | n/a | n/a |

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
| _(floor: empty program)_ | _5.547_ | _91.885_ | _**97.432**_ | _52.837_ | _74.755_ | _54.143_ |
| `lcg` | 5.984 | 100.794 | **106.778** | 51.256 | 76.650 | 63.446 |
| `packet_classifier` | 6.029 | 108.541 | **114.570** | 54.031 | 76.840 | 62.171 |
| `ring_write` | 11.453 | 107.141 | **118.594** | 59.047 | 76.797 | 64.458 |
| `histogram_bins` | 11.272 | 106.615 | **117.887** | 58.968 | 102.391 | 68.615 |
| `prefix_scan` | 11.124 | 106.997 | **118.121** | 57.059 | 81.384 | 65.267 |
| `binary_search` | 11.301 | 108.736 | **120.037** | 59.828 | 81.109 | 65.575 |
| `sort_window` | 11.734 | 106.701 | **118.435** | 59.670 | 85.393 | 69.220 |
| `bloom_filter` | 11.988 | 105.591 | **117.579** | 59.925 | 81.726 | 66.135 |
| `hash_join` | 13.257 | 172.981 | **186.238** | 57.413 | 143.719 | 97.191 |
| `sieve` | 11.277 | 101.104 | **112.381** | 56.785 | 80.491 | 70.527 |
| `fib` | 5.812 | 98.227 | **104.039** | 50.690 | 73.177 | 60.542 |
| `collatz` | 5.860 | 100.869 | **106.729** | 50.951 | 73.744 | 60.576 |
| `matmul` | 11.329 | 102.597 | **113.926** | 56.948 | 83.153 | 75.528 |
| `json_parse` | 29.872 | 227.468 | **257.340** | 75.869 | 112.031 | 132.681 |
| `nbody` | 12.179 | 107.044 | **119.223** | 59.296 | 96.803 | 89.196 |
| `chacha20` | 39.211 | 438.454 | **477.665** | 85.025 | 102.639 | 94.276 |
| `poly1305` | 33.602 | 271.648 | **305.250** | 79.315 | 105.978 | 105.772 |
| `blake2b` | 23.926 | 225.079 | **249.005** | 69.454 | 107.669 | 101.187 |
| `sha512` | 22.396 | 287.793 | **310.189** | 67.548 | 103.778 | 92.618 |
| `x25519` | 31.803 | 839.752 | **871.555** | 82.556 | 731.076 | 331.046 |

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
