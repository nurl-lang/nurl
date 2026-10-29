# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-29T05:34:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16367524 KiB |
| Commit | `694c395376e85107f7e054c4ce9db9078169e06a` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40823708561 |
| NURL | `v0.80.0-38-g694c3953` |
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
| _(floor: empty program)_ | _1.249_ | _1.216_ | _1.418_ | _19.110_ | _13.108_ |
| `lcg` | **28.479** | 28.561 | 29.764 | 1104.363 | 2929.279 |
| `packet_classifier` | 42.354 | **42.006** | 42.552 | 131.356 | 2672.498 |
| `ring_write` | 29.691 | 29.464 | **29.362** | 50.359 | 3548.341 |
| `histogram_bins` | 29.270 | **28.348** | 28.879 | 49.892 | 3434.052 |
| `prefix_scan` | 16.590 | **16.515** | 16.530 | 48.560 | 2567.789 |
| `binary_search` | 15.684 | **15.233** | 16.283 | 74.529 | 3644.409 |
| `sort_window` | 21.099 | **20.933** | 21.322 | 140.839 | 7217.784 |
| `bloom_filter` | 9.117 | **9.112** | 9.300 | 1646.398 | 4369.301 |
| `hash_join` | **15.671** | 16.356 | 17.288 | 1923.909 | 4599.748 |
| `sieve` | 15.689 | **15.161** | 15.352 | 50.225 | 1808.351 |
| `fib` | **18.271** | 18.492 | 19.274 | 76.911 | 651.586 |
| `collatz` | 9.111 | **8.996** | 9.170 | 35.911 | 402.791 |
| `matmul` | 21.015 | **20.201** | 20.652 | 51.909 | 1755.516 |
| `json_parse` | **5.040** | 5.152 | 6.832 | 22.781 | 32.320 |
| `nbody` | **16.702** | 24.208 | 16.797 | 56.429 | 1457.480 |
| `chacha20` | **6.747** | 19.416 | 18.555 | n/a | n/a |
| `poly1305` | **8.713** | 26.289 | 15.760 | n/a | n/a |
| `blake2b` | **25.017** | 40.575 | 46.290 | n/a | n/a |
| `sha512` | **30.337** | 32.532 | 32.453 | n/a | n/a |
| `x25519` | **18.544** | 28.860 | 29.479 | n/a | n/a |

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
| _(floor: empty program)_ | _3.936_ | _97.304_ | _**101.240**_ | _55.474_ | _72.957_ | _54.900_ |
| `lcg` | 4.007 | 107.891 | **111.898** | 55.684 | 80.696 | 89.684 |
| `packet_classifier` | 4.042 | 105.300 | **109.342** | 53.942 | 80.759 | 62.758 |
| `ring_write` | 11.168 | 103.490 | **114.658** | 58.670 | 79.515 | 61.260 |
| `histogram_bins` | 10.757 | 104.774 | **115.531** | 58.322 | 86.495 | 64.850 |
| `prefix_scan` | 10.672 | 105.249 | **115.921** | 57.944 | 81.007 | 63.339 |
| `binary_search` | 10.594 | 99.491 | **110.085** | 56.910 | 77.676 | 64.996 |
| `sort_window` | 10.878 | 106.543 | **117.421** | 59.366 | 86.828 | 68.083 |
| `bloom_filter` | 11.163 | 106.182 | **117.345** | 59.018 | 84.323 | 65.795 |
| `hash_join` | 13.528 | 182.800 | **196.328** | 61.173 | 154.624 | 98.337 |
| `sieve` | 10.698 | 101.727 | **112.425** | 59.674 | 84.466 | 69.929 |
| `fib` | 3.805 | 100.885 | **104.690** | 50.510 | 74.602 | 58.458 |
| `collatz` | 3.855 | 102.898 | **106.753** | 52.325 | 75.907 | 58.222 |
| `matmul` | 10.983 | 94.890 | **105.873** | 55.158 | 80.604 | 71.029 |
| `json_parse` | 29.639 | 287.925 | **317.564** | 74.614 | 114.777 | 130.774 |
| `nbody` | 11.529 | 102.157 | **113.686** | 56.536 | 93.138 | 79.547 |
| `chacha20` | 34.766 | 514.492 | **549.258** | 88.071 | 103.147 | 92.084 |
| `poly1305` | 25.684 | 321.185 | **346.869** | 72.207 | 106.867 | 102.209 |
| `blake2b` | 23.861 | 242.315 | **266.176** | 69.587 | 103.447 | 95.683 |
| `sha512` | 22.981 | 285.516 | **308.497** | 67.848 | 100.192 | 95.629 |
| `x25519` | 31.297 | 761.515 | **792.812** | 76.519 | 728.671 | 322.359 |

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
