# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-11T16:10:32Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `efde0a5a88baf97c2ce442b52aa588007167caae` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38153929055 |
| NURL | `v0.72.0-5-gefde0a5a` |
| C | Ubuntu clang version 18.1.3 (1ubuntu1) |
| Rust | rustc 1.99.0 (b940084d7 2026-09-28) |
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
| _(floor: empty program)_ | _1.436_ | _1.399_ | _1.613_ | _21.766_ | _17.255_ |
| `lcg` | 38.953 | **38.917** | 39.065 | 1911.775 | 5213.309 |
| `packet_classifier` | 56.246 | **56.151** | 56.300 | 161.095 | 4372.682 |
| `ring_write` | 42.280 | **42.204** | 42.489 | 68.298 | 6564.645 |
| `histogram_bins` | **39.353** | 40.531 | 40.819 | 65.108 | 6096.143 |
| `prefix_scan` | 21.666 | **21.622** | 21.769 | 63.752 | 4490.883 |
| `binary_search` | 39.412 | **38.010** | 40.680 | 104.845 | 6469.408 |
| `sort_window` | **26.416** | 26.483 | 26.657 | 197.190 | 11595.807 |
| `bloom_filter` | **15.343** | 17.850 | 18.238 | 2819.494 | 7739.329 |
| `hash_join` | **26.483** | 27.921 | 29.096 | 3419.242 | 8465.342 |
| `sieve` | 18.382 | **17.938** | 18.213 | 64.832 | 3521.703 |
| `fib` | **25.205** | 29.711 | 30.001 | 130.532 | 1364.161 |
| `collatz` | 12.191 | **12.133** | 12.383 | 49.176 | 748.457 |
| `matmul` | **33.451** | 33.543 | 33.822 | 75.576 | 3106.566 |
| `json_parse` | **8.139** | 8.614 | 11.915 | 35.144 | 38.959 |
| `nbody` | **25.041** | 39.677 | 25.223 | 98.422 | 3173.782 |
| `chacha20` | **7.467** | 40.347 | 33.643 | n/a | n/a |
| `poly1305` | 23.386 | 31.747 | **21.087** | n/a | n/a |
| `blake2b` | **43.880** | 64.972 | 68.862 | n/a | n/a |
| `sha512` | **47.061** | 50.402 | 49.306 | n/a | n/a |
| `x25519` | **44.609** | 48.358 | 50.200 | n/a | n/a |

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
| _(floor: empty program)_ | _3.589_ | _100.016_ | _**103.605**_ | _58.312_ | _74.876_ | _58.353_ |
| `lcg` | 3.770 | 108.793 | **112.563** | 58.974 | 85.778 | 64.435 |
| `packet_classifier` | 3.853 | 108.435 | **112.288** | 58.468 | 87.522 | 65.542 |
| `ring_write` | 4.129 | 111.810 | **115.939** | 60.621 | 89.534 | 67.375 |
| `histogram_bins` | 4.259 | 120.228 | **124.487** | 60.443 | 106.113 | 75.519 |
| `prefix_scan` | 4.359 | 112.126 | **116.485** | 59.335 | 94.575 | 71.764 |
| `binary_search` | 4.568 | 110.650 | **115.218** | 59.968 | 88.738 | 71.368 |
| `sort_window` | 4.810 | 115.907 | **120.717** | 61.305 | 101.501 | 77.559 |
| `bloom_filter` | 5.430 | 118.838 | **124.268** | 63.491 | 102.590 | 73.443 |
| `hash_join` | 9.281 | 262.235 | **271.516** | 66.174 | 218.393 | 121.221 |
| `sieve` | 4.645 | 114.452 | **119.097** | 61.944 | 103.409 | 80.303 |
| `fib` | 4.123 | 112.979 | **117.102** | 60.437 | 88.254 | 67.053 |
| `collatz` | 4.222 | 115.775 | **119.997** | 61.484 | 91.562 | 67.794 |
| `matmul` | 6.165 | 116.074 | **122.239** | 63.465 | 110.539 | 90.324 |
| `json_parse` | 48.312 | 483.586 | **531.898** | 108.276 | 160.680 | 166.570 |
| `nbody` | 6.970 | 132.921 | **139.891** | 63.580 | 127.107 | 103.980 |
| `chacha20` | 51.737 | 604.154 | **655.891** | 108.981 | 139.750 | 116.591 |
| `poly1305` | 33.717 | 266.902 | **300.619** | 91.171 | 141.341 | 130.036 |
| `blake2b` | 35.749 | 356.219 | **391.968** | 92.986 | 148.300 | 124.833 |
| `sha512` | 35.897 | 466.434 | **502.331** | 92.379 | 134.740 | 108.703 |
| `x25519` | 43.951 | 716.004 | **759.955** | 100.835 | 1227.048 | 513.963 |

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
