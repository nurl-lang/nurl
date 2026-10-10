# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-10T19:47:41Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `95dcb64ec83858655d131346334dacdd9c34f7d9` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/38080882274 |
| NURL | `v0.72.0-3-g95dcb64e` |
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
| _(floor: empty program)_ | _1.217_ | _1.200_ | _1.372_ | _18.961_ | _13.980_ |
| `lcg` | **34.146** | 34.207 | 34.339 | 1408.680 | 4257.161 |
| `packet_classifier` | **49.168** | 49.226 | 49.347 | 124.113 | 3617.913 |
| `ring_write` | **36.873** | 36.885 | 37.065 | 58.044 | 4943.158 |
| `histogram_bins` | **34.579** | 34.609 | 34.650 | 58.466 | 4897.937 |
| `prefix_scan` | 18.931 | **18.906** | 19.134 | 56.019 | 3631.082 |
| `binary_search` | 32.129 | **27.626** | 33.568 | 87.584 | 5103.652 |
| `sort_window` | 23.198 | **23.197** | 23.332 | 128.985 | 9530.381 |
| `bloom_filter` | **13.352** | 14.547 | 16.013 | 2109.606 | 6126.896 |
| `hash_join` | **21.395** | 22.219 | 23.398 | 2645.181 | 6472.211 |
| `sieve` | 16.129 | **15.811** | 16.023 | 58.501 | 2659.704 |
| `fib` | **21.548** | 25.702 | 25.837 | 111.073 | 1005.058 |
| `collatz` | **10.574** | 10.593 | 10.793 | 40.688 | 583.805 |
| `matmul` | 35.759 | 35.841 | **35.299** | 66.987 | 2652.173 |
| `json_parse` | **6.368** | 6.836 | 9.351 | 29.731 | 30.507 |
| `nbody` | **20.757** | 34.844 | 20.843 | 74.897 | 2508.096 |
| `chacha20` | **6.937** | 35.683 | 27.601 | n/a | n/a |
| `poly1305` | 20.394 | 31.210 | **18.463** | n/a | n/a |
| `blake2b` | **37.855** | 55.570 | 60.621 | n/a | n/a |
| `sha512` | **38.504** | 40.123 | 42.240 | n/a | n/a |
| `x25519` | **38.222** | 41.950 | 43.409 | n/a | n/a |

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
| _(floor: empty program)_ | _3.253_ | _86.894_ | _**90.147**_ | _53.403_ | _71.559_ | _52.767_ |
| `lcg` | 3.362 | 96.608 | **99.970** | 54.031 | 78.903 | 58.338 |
| `packet_classifier` | 3.492 | 97.401 | **100.893** | 54.267 | 80.446 | 59.419 |
| `ring_write` | 3.622 | 98.112 | **101.734** | 54.443 | 81.394 | 61.431 |
| `histogram_bins` | 3.691 | 104.123 | **107.814** | 54.908 | 93.355 | 66.560 |
| `prefix_scan` | 3.848 | 99.919 | **103.767** | 54.785 | 85.195 | 63.554 |
| `binary_search` | 3.946 | 99.439 | **103.385** | 54.774 | 81.666 | 64.923 |
| `sort_window` | 4.130 | 101.543 | **105.673** | 55.374 | 89.555 | 68.116 |
| `bloom_filter` | 4.553 | 101.263 | **105.816** | 56.241 | 88.290 | 64.739 |
| `hash_join` | 7.650 | 206.459 | **214.109** | 57.794 | 170.580 | 100.504 |
| `sieve` | 3.993 | 97.633 | **101.626** | 54.662 | 88.799 | 69.236 |
| `fib` | 3.602 | 97.678 | **101.280** | 54.522 | 79.771 | 59.681 |
| `collatz` | 3.727 | 99.210 | **102.937** | 54.880 | 81.056 | 59.655 |
| `matmul` | 5.133 | 99.871 | **105.004** | 56.475 | 90.694 | 76.288 |
| `json_parse` | 39.860 | 365.444 | **405.304** | 91.902 | 130.604 | 139.216 |
| `nbody` | 5.853 | 113.207 | **119.060** | 56.976 | 105.434 | 89.381 |
| `chacha20` | 41.356 | 466.046 | **507.402** | 92.284 | 115.934 | 98.074 |
| `poly1305` | 27.203 | 203.439 | **230.642** | 78.479 | 117.723 | 109.966 |
| `blake2b` | 28.938 | 281.036 | **309.974** | 80.715 | 121.412 | 105.732 |
| `sha512` | 29.192 | 359.335 | **388.527** | 80.578 | 115.666 | 94.217 |
| `x25519` | 35.290 | 544.783 | **580.073** | 87.016 | 935.353 | 405.790 |

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
