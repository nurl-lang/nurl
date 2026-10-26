# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-26T09:04:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | AMD EPYC 9V45 96-Core Processor (4 logical cores) |
| Memory | 16373452 KiB |
| Commit | `3bd7aedaf971687346dc8904e746b2e6315f6441` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40296173224 |
| NURL | `v0.78.0-10-g3bd7aeda` |
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
| _(floor: empty program)_ | _1.106_ | _1.083_ | _1.290_ | _17.013_ | _11.880_ |
| `lcg` | 28.076 | **28.051** | 29.211 | 1083.709 | 2899.675 |
| `packet_classifier` | 40.685 | 41.502 | **40.473** | 126.085 | 2540.095 |
| `ring_write` | 29.428 | **28.147** | 28.395 | 49.831 | 3522.631 |
| `histogram_bins` | **29.135** | 29.251 | 29.604 | 50.531 | 3301.897 |
| `prefix_scan` | **15.691** | 16.049 | 15.983 | 45.922 | 2511.784 |
| `binary_search` | **15.053** | 15.087 | 16.050 | 69.892 | 3583.254 |
| `sort_window` | 21.214 | **19.264** | 19.597 | 130.327 | 6187.486 |
| `bloom_filter` | 8.585 | **8.462** | 8.617 | 1609.191 | 4441.210 |
| `hash_join` | **15.918** | 17.147 | 17.610 | 1896.173 | 4534.642 |
| `sieve` | 12.352 | 12.160 | **11.918** | 45.331 | 1796.172 |
| `fib` | 19.199 | **18.619** | 19.345 | 74.488 | 662.980 |
| `collatz` | 8.935 | **8.884** | 9.131 | 36.714 | 416.935 |
| `matmul` | **19.268** | 19.844 | 20.559 | 53.142 | 1673.034 |
| `json_parse` | **4.880** | 5.055 | 6.815 | 23.996 | 23.313 |
| `nbody` | **16.214** | 24.841 | 16.514 | 57.297 | 1461.957 |
| `chacha20` | **6.704** | 19.760 | 19.261 | n/a | n/a |
| `poly1305` | **8.284** | 25.676 | 15.000 | n/a | n/a |
| `blake2b` | **25.150** | 42.929 | 48.615 | n/a | n/a |
| `sha512` | **30.162** | 33.088 | 32.267 | n/a | n/a |
| `x25519` | **25.491** | 29.303 | 31.248 | n/a | n/a |

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
| _(floor: empty program)_ | _3.385_ | _89.518_ | _**92.903**_ | _49.635_ | _68.203_ | _42.443_ |
| `lcg` | 3.326 | 91.499 | **94.825** | 47.221 | 72.381 | 46.359 |
| `packet_classifier` | 3.544 | 94.847 | **98.391** | 48.875 | 72.596 | 46.580 |
| `ring_write` | 9.069 | 97.744 | **106.813** | 54.108 | 71.879 | 47.350 |
| `histogram_bins` | 9.443 | 98.044 | **107.487** | 55.200 | 84.008 | 52.506 |
| `prefix_scan` | 9.248 | 98.528 | **107.776** | 55.712 | 76.391 | 50.110 |
| `binary_search` | 9.190 | 99.011 | **108.201** | 55.843 | 74.127 | 52.152 |
| `sort_window` | 9.289 | 95.429 | **104.718** | 54.182 | 81.677 | 56.280 |
| `bloom_filter` | 9.697 | 102.772 | **112.469** | 55.791 | 80.040 | 52.517 |
| `hash_join` | 11.939 | 176.905 | **188.844** | 57.693 | 139.531 | 79.519 |
| `sieve` | 9.579 | 99.740 | **109.319** | 56.372 | 80.367 | 58.396 |
| `fib` | 3.588 | 97.295 | **100.883** | 49.198 | 70.243 | 47.141 |
| `collatz` | 3.749 | 95.912 | **99.661** | 48.514 | 74.095 | 47.857 |
| `matmul` | 10.190 | 98.565 | **108.755** | 56.077 | 83.627 | 60.389 |
| `json_parse` | 29.167 | 306.533 | **335.700** | 73.010 | 113.210 | 114.045 |
| `nbody` | 10.722 | 102.646 | **113.368** | 57.111 | 93.920 | 70.718 |
| `chacha20` | 30.710 | 491.435 | **522.145** | 73.304 | 102.618 | 78.804 |
| `poly1305` | 24.669 | 319.207 | **343.876** | 69.477 | 100.217 | 85.256 |
| `blake2b` | 22.677 | 239.515 | **262.192** | 65.697 | 103.753 | 82.964 |
| `sha512` | 22.036 | 295.832 | **317.868** | 67.520 | 101.304 | 79.241 |
| `x25519` | 23.265 | 503.521 | **526.786** | 68.553 | 731.476 | 312.576 |

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
