# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-20T07:36:21Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 6.17.0-1022-azure x86_64` |
| CPU | Intel(R) Xeon(R) 6973P-C (4 logical cores) |
| Memory | 16372440 KiB |
| Commit | `c9289772322d426cfb5098d905d4890a472d39f6` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/39387049353 |
| NURL | `v0.74.0-12-gc9289772` |
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
| _(floor: empty program)_ | _1.043_ | _1.047_ | _1.193_ | _19.904_ | _15.647_ |
| `lcg` | **35.129** | 35.283 | 35.246 | 1253.188 | 3650.600 |
| `packet_classifier` | 61.100 | **60.586** | 60.937 | 145.865 | 2963.700 |
| `ring_write` | 38.025 | 38.415 | **37.991** | 60.398 | 4384.074 |
| `histogram_bins` | 36.044 | **35.708** | 36.335 | 60.302 | 4068.282 |
| `prefix_scan` | 19.344 | 19.144 | **19.125** | 58.942 | 3043.253 |
| `binary_search` | 31.852 | **23.294** | 33.602 | 99.812 | 5034.073 |
| `sort_window` | 34.849 | **34.798** | 35.896 | 158.864 | 8588.873 |
| `bloom_filter` | **12.012** | 12.104 | 12.484 | 2094.963 | 5554.106 |
| `hash_join` | **21.048** | 21.239 | 22.363 | 2626.632 | 6027.183 |
| `sieve` | 36.280 | **35.165** | 35.686 | 77.792 | 2318.772 |
| `fib` | **20.242** | 23.474 | 24.056 | 96.391 | 778.101 |
| `collatz` | **13.003** | 13.174 | 14.028 | 53.743 | 490.812 |
| `matmul` | 17.010 | 16.578 | **15.359** | 62.228 | 2117.190 |
| `json_parse` | **5.910** | 6.625 | 8.091 | 27.412 | 28.135 |
| `nbody` | **17.848** | 26.365 | 18.894 | 75.059 | 1856.716 |
| `chacha20` | **7.211** | 31.726 | 27.823 | n/a | n/a |
| `poly1305` | **20.865** | 29.221 | 21.308 | n/a | n/a |
| `blake2b` | **37.519** | 45.159 | 47.531 | n/a | n/a |
| `sha512` | **36.373** | 40.763 | 45.796 | n/a | n/a |
| `x25519` | 37.102 | 36.310 | **35.864** | n/a | n/a |

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
| _(floor: empty program)_ | _3.162_ | _74.944_ | _**78.106**_ | _45.331_ | _54.974_ | _46.358_ |
| `lcg` | 3.379 | 87.541 | **90.920** | 44.953 | 63.403 | 54.259 |
| `packet_classifier` | 3.572 | 86.008 | **89.580** | 47.221 | 64.944 | 54.628 |
| `ring_write` | 10.268 | 94.556 | **104.824** | 55.527 | 69.387 | 55.713 |
| `histogram_bins` | 10.257 | 104.156 | **114.413** | 55.662 | 81.840 | 59.711 |
| `prefix_scan` | 10.575 | 92.562 | **103.137** | 55.864 | 75.849 | 58.214 |
| `binary_search` | 10.553 | 95.129 | **105.682** | 54.985 | 70.863 | 64.455 |
| `sort_window` | 10.641 | 94.428 | **105.069** | 55.096 | 77.070 | 64.964 |
| `bloom_filter` | 11.234 | 94.946 | **106.180** | 56.102 | 74.507 | 60.583 |
| `hash_join` | 14.208 | 215.062 | **229.270** | 60.348 | 158.180 | 97.147 |
| `sieve` | 10.693 | 89.517 | **100.210** | 52.689 | 72.652 | 63.868 |
| `fib` | 3.580 | 84.958 | **88.538** | 45.335 | 62.910 | 52.961 |
| `collatz` | 3.780 | 86.166 | **89.946** | 44.775 | 64.400 | 54.536 |
| `matmul` | 11.189 | 88.815 | **100.004** | 52.010 | 70.524 | 67.286 |
| `json_parse` | 35.443 | 404.618 | **440.061** | 82.980 | 124.211 | 143.835 |
| `nbody` | 12.130 | 107.848 | **119.978** | 55.038 | 94.976 | 85.621 |
| `chacha20` | 34.552 | 672.030 | **706.582** | 82.433 | 107.139 | 95.550 |
| `poly1305` | 24.352 | 213.945 | **238.297** | 78.676 | 107.916 | 110.818 |
| `blake2b` | 27.423 | 331.942 | **359.365** | 76.152 | 117.054 | 108.745 |
| `sha512` | 27.179 | 415.764 | **442.943** | 73.602 | 105.145 | 94.473 |
| `x25519` | 31.555 | 637.989 | **669.544** | 79.048 | 989.074 | 405.788 |

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
