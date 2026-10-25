# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-25T05:34:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16373448 KiB |
| Commit | `5bcf6a6066c39b0e7ce2f5554eb949c27e71951f` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40165692768 |
| NURL | `v0.78.0-2-g5bcf6a60` |
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
| _(floor: empty program)_ | _1.224_ | _1.187_ | _1.413_ | _18.932_ | _14.023_ |
| `lcg` | 34.173 | **34.168** | 34.342 | 1408.872 | 4207.388 |
| `packet_classifier` | 49.232 | **49.218** | 49.392 | 123.795 | 3539.947 |
| `ring_write` | 36.980 | **36.909** | 37.169 | 58.301 | 5102.327 |
| `histogram_bins` | **34.534** | 34.542 | 34.680 | 58.212 | 4843.133 |
| `prefix_scan` | 18.960 | **18.890** | 19.060 | 56.557 | 3783.430 |
| `binary_search` | 28.039 | **27.632** | 33.535 | 86.693 | 5638.602 |
| `sort_window` | 23.217 | **23.211** | 23.367 | 128.450 | 8731.005 |
| `bloom_filter` | **13.394** | 14.487 | 16.012 | 2112.398 | 6478.090 |
| `hash_join` | **21.458** | 22.171 | 23.356 | 2664.384 | 6446.064 |
| `sieve` | 15.814 | **15.472** | 15.603 | 55.167 | 2591.150 |
| `fib` | 25.683 | **25.672** | 25.797 | 110.591 | 1000.031 |
| `collatz` | 10.648 | **10.551** | 10.770 | 39.696 | 579.797 |
| `matmul` | 36.123 | 36.087 | **35.660** | 64.556 | 2757.783 |
| `json_parse` | **6.162** | 6.821 | 9.389 | 29.372 | 30.309 |
| `nbody` | 20.881 | 34.826 | **20.814** | 74.336 | 2500.308 |
| `chacha20` | **6.707** | 35.754 | 27.564 | n/a | n/a |
| `poly1305` | **9.971** | 31.200 | 18.505 | n/a | n/a |
| `blake2b` | **37.594** | 55.513 | 60.522 | n/a | n/a |
| `sha512` | **38.692** | 40.390 | 42.356 | n/a | n/a |
| `x25519` | **38.148** | 42.098 | 43.386 | n/a | n/a |

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
| _(floor: empty program)_ | _3.870_ | _115.890_ | _**119.760**_ | _55.019_ | _69.285_ | _46.743_ |
| `lcg` | 3.913 | 105.849 | **109.762** | 55.057 | 78.080 | 49.111 |
| `packet_classifier` | 3.956 | 105.422 | **109.378** | 54.951 | 78.915 | 49.540 |
| `ring_write` | 11.422 | 107.596 | **119.018** | 63.080 | 80.489 | 51.184 |
| `histogram_bins` | 11.645 | 109.028 | **120.673** | 62.711 | 92.466 | 56.885 |
| `prefix_scan` | 11.376 | 106.890 | **118.266** | 61.400 | 83.698 | 53.305 |
| `binary_search` | 11.804 | 108.850 | **120.654** | 63.202 | 82.070 | 54.221 |
| `sort_window` | 11.652 | 108.845 | **120.497** | 63.018 | 88.690 | 58.850 |
| `bloom_filter` | 12.173 | 111.015 | **123.188** | 63.157 | 88.060 | 55.101 |
| `hash_join` | 14.697 | 207.688 | **222.385** | 65.235 | 169.675 | 89.398 |
| `sieve` | 11.693 | 108.023 | **119.716** | 62.208 | 87.213 | 58.619 |
| `fib` | 4.024 | 103.347 | **107.371** | 54.131 | 79.093 | 49.580 |
| `collatz` | 4.189 | 105.432 | **109.621** | 54.484 | 79.922 | 49.986 |
| `matmul` | 12.792 | 107.593 | **120.385** | 63.914 | 90.089 | 65.489 |
| `json_parse` | 36.759 | 371.933 | **408.692** | 88.207 | 129.626 | 125.707 |
| `nbody` | 13.648 | 114.979 | **128.627** | 64.414 | 106.310 | 77.763 |
| `chacha20` | 42.100 | 617.866 | **659.966** | 92.551 | 116.305 | 86.671 |
| `poly1305` | 32.111 | 395.461 | **427.572** | 82.742 | 117.658 | 97.105 |
| `blake2b` | 29.592 | 297.172 | **326.764** | 80.474 | 122.100 | 94.092 |
| `sha512` | 29.385 | 361.177 | **390.562** | 79.906 | 116.185 | 83.419 |
| `x25519` | 29.373 | 627.267 | **656.640** | 81.292 | 931.992 | 387.123 |

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
