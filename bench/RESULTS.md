# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-28T16:54:18Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `14cafa2426dcbdd675ea37f442824e6412c3baf0` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40729713308 |
| NURL | `v0.80.0-5-g14cafa24` |
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
| _(floor: empty program)_ | _1.261_ | _1.209_ | _1.430_ | _18.372_ | _12.242_ |
| `lcg` | 30.511 | 31.287 | **30.345** | 1128.377 | 3068.963 |
| `packet_classifier` | **43.159** | 43.228 | 43.240 | 134.590 | 2749.678 |
| `ring_write` | **30.020** | 30.098 | 30.534 | 54.142 | 3724.974 |
| `histogram_bins` | 31.695 | **30.126** | 30.501 | 53.576 | 3501.489 |
| `prefix_scan` | **16.609** | 16.713 | 16.850 | 52.481 | 2712.369 |
| `binary_search` | 15.327 | **15.204** | 16.371 | 73.401 | 3671.160 |
| `sort_window` | 20.987 | **20.717** | 21.172 | 139.030 | 6446.032 |
| `bloom_filter` | 9.281 | **9.218** | 9.602 | 1677.062 | 4647.346 |
| `hash_join` | **16.996** | 17.799 | 18.859 | 2010.952 | 4854.746 |
| `sieve` | 20.307 | **15.660** | 15.924 | 51.570 | 1875.377 |
| `fib` | 20.439 | **19.765** | 20.016 | 82.918 | 718.753 |
| `collatz` | 9.792 | **9.748** | 10.071 | 40.503 | 427.011 |
| `matmul` | 21.245 | **21.049** | 21.572 | 58.691 | 1725.656 |
| `json_parse` | **5.411** | 5.786 | 7.464 | 28.974 | 27.303 |
| `nbody` | **17.318** | 25.381 | 17.778 | 62.851 | 1576.205 |
| `chacha20` | **7.178** | 20.459 | 20.312 | n/a | n/a |
| `poly1305` | **9.144** | 27.237 | 16.135 | n/a | n/a |
| `blake2b` | **28.904** | 45.419 | 49.156 | n/a | n/a |
| `sha512` | **31.056** | 33.601 | 33.020 | n/a | n/a |
| `x25519` | **19.372** | 29.884 | 31.142 | n/a | n/a |

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
| _(floor: empty program)_ | _3.914_ | _102.618_ | _**106.532**_ | _55.820_ | _77.131_ | _53.285_ |
| `lcg` | 3.947 | 109.024 | **112.971** | 55.832 | 84.385 | 65.142 |
| `packet_classifier` | 4.246 | 112.928 | **117.174** | 57.424 | 86.328 | 65.619 |
| `ring_write` | 11.373 | 114.035 | **125.408** | 63.650 | 86.670 | 66.899 |
| `histogram_bins` | 10.889 | 110.345 | **121.234** | 60.627 | 93.099 | 68.223 |
| `prefix_scan` | 11.360 | 114.125 | **125.485** | 64.005 | 91.830 | 69.302 |
| `binary_search` | 11.192 | 110.424 | **121.616** | 64.909 | 86.463 | 65.722 |
| `sort_window` | 11.335 | 111.968 | **123.303** | 62.746 | 92.356 | 70.429 |
| `bloom_filter` | 11.877 | 114.373 | **126.250** | 63.464 | 91.141 | 71.250 |
| `hash_join` | 14.397 | 192.299 | **206.696** | 67.305 | 159.724 | 135.204 |
| `sieve` | 11.596 | 114.215 | **125.811** | 63.537 | 93.525 | 78.157 |
| `fib` | 4.381 | 115.859 | **120.240** | 57.022 | 92.143 | 65.237 |
| `collatz` | 4.396 | 118.385 | **122.781** | 59.412 | 89.624 | 68.512 |
| `matmul` | 12.195 | 114.238 | **126.433** | 65.359 | 96.577 | 84.471 |
| `json_parse` | 33.640 | 337.869 | **371.509** | 86.859 | 128.993 | 152.608 |
| `nbody` | 12.901 | 118.439 | **131.340** | 65.351 | 107.851 | 91.328 |
| `chacha20` | 38.668 | 531.065 | **569.733** | 91.073 | 120.104 | 102.964 |
| `poly1305` | 30.372 | 356.830 | **387.202** | 82.669 | 119.046 | 115.645 |
| `blake2b` | 27.747 | 269.375 | **297.122** | 81.271 | 122.079 | 111.765 |
| `sha512` | 26.701 | 325.771 | **352.472** | 78.237 | 116.387 | 102.700 |
| `x25519` | 34.375 | 749.769 | **784.144** | 86.550 | 780.192 | 352.348 |

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
