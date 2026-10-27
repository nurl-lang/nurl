# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-27T15:22:27Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `a8f64496c30dcdbcd9d2441194723fe576b396e1` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40529315499 |
| NURL | `v0.79.0` |
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
| _(floor: empty program)_ | _1.433_ | _1.425_ | _1.616_ | _23.898_ | _17.373_ |
| `lcg` | **39.058** | 39.059 | 39.259 | 1885.961 | 5138.890 |
| `packet_classifier` | 56.373 | **56.202** | 56.467 | 162.324 | 4422.629 |
| `ring_write` | **42.077** | 42.115 | 42.294 | 64.995 | 6366.989 |
| `histogram_bins` | 40.724 | **40.548** | 40.711 | 66.417 | 6140.339 |
| `prefix_scan` | **21.515** | 21.611 | 21.834 | 65.107 | 4636.970 |
| `binary_search` | 38.306 | **38.077** | 40.749 | 106.345 | 5984.867 |
| `sort_window` | 26.547 | **26.534** | 26.691 | 197.325 | 11344.551 |
| `bloom_filter` | **15.442** | 17.796 | 18.318 | 2866.700 | 7510.078 |
| `hash_join` | **26.841** | 27.877 | 29.206 | 3418.715 | 8256.850 |
| `sieve` | 21.306 | 20.885 | **20.222** | 68.334 | 3240.311 |
| `fib` | 29.920 | **29.866** | 30.080 | 135.191 | 1369.662 |
| `collatz` | **12.280** | 12.325 | 12.454 | 50.521 | 734.923 |
| `matmul` | 33.524 | **33.421** | 33.653 | 76.706 | 3110.202 |
| `json_parse` | **8.245** | 8.579 | 11.786 | 36.223 | 39.181 |
| `nbody` | **25.165** | 39.710 | 25.218 | 101.041 | 3065.322 |
| `chacha20` | **7.260** | 42.488 | 33.882 | n/a | n/a |
| `poly1305` | **11.963** | 32.053 | 21.424 | n/a | n/a |
| `blake2b` | **43.942** | 65.111 | 69.530 | n/a | n/a |
| `sha512` | **46.954** | 50.871 | 49.767 | n/a | n/a |
| `x25519` | **44.391** | 48.771 | 49.346 | n/a | n/a |

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
| _(floor: empty program)_ | _4.359_ | _114.413_ | _**118.772**_ | _62.900_ | _78.807_ | _52.893_ |
| `lcg` | 4.454 | 127.000 | **131.454** | 62.619 | 89.306 | 57.369 |
| `packet_classifier` | 4.547 | 127.230 | **131.777** | 62.637 | 91.163 | 58.444 |
| `ring_write` | 15.085 | 130.454 | **145.539** | 73.840 | 93.660 | 60.184 |
| `histogram_bins` | 15.194 | 126.764 | **141.958** | 71.432 | 105.674 | 66.093 |
| `prefix_scan` | 15.188 | 130.577 | **145.765** | 74.230 | 100.162 | 63.010 |
| `binary_search` | 15.249 | 128.804 | **144.053** | 73.680 | 92.378 | 63.749 |
| `sort_window` | 15.336 | 130.152 | **145.488** | 73.048 | 101.902 | 68.076 |
| `bloom_filter` | 16.138 | 134.374 | **150.512** | 74.783 | 100.171 | 64.885 |
| `hash_join` | 20.148 | 271.866 | **292.014** | 79.215 | 222.244 | 112.114 |
| `sieve` | 15.640 | 132.062 | **147.702** | 75.038 | 105.143 | 71.392 |
| `fib` | 4.720 | 131.095 | **135.815** | 65.040 | 92.911 | 59.687 |
| `collatz` | 4.815 | 131.218 | **136.033** | 64.843 | 94.260 | 61.229 |
| `matmul` | 16.981 | 133.625 | **150.606** | 76.044 | 107.433 | 79.758 |
| `json_parse` | 50.242 | 490.159 | **540.401** | 108.363 | 164.025 | 155.511 |
| `nbody` | 18.031 | 139.596 | **157.627** | 75.618 | 127.135 | 96.454 |
| `chacha20` | 59.342 | 778.599 | **837.941** | 119.437 | 146.581 | 108.039 |
| `poly1305` | 44.914 | 524.670 | **569.584** | 104.392 | 148.164 | 125.704 |
| `blake2b` | 40.662 | 392.201 | **432.863** | 101.620 | 153.251 | 118.565 |
| `sha512` | 40.013 | 486.187 | **526.200** | 100.820 | 143.681 | 104.264 |
| `x25519` | 40.192 | 845.543 | **885.735** | 99.322 | 1234.182 | 495.218 |

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
