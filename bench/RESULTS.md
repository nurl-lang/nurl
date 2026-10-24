# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-24T16:28:29Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `c57eb6148c79c2ef2198e2b0915c5b27f3c97603` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/40111227475 |
| NURL | `v0.78.0` |
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
| _(floor: empty program)_ | _1.457_ | _1.457_ | _1.611_ | _23.552_ | _17.309_ |
| `lcg` | 39.264 | **39.178** | 39.420 | 1906.800 | 5216.646 |
| `packet_classifier` | **56.329** | 56.338 | 56.634 | 163.936 | 4314.185 |
| `ring_write` | 42.414 | **42.373** | 42.623 | 66.756 | 7143.201 |
| `histogram_bins` | 40.816 | **40.774** | 40.936 | 66.784 | 6246.046 |
| `prefix_scan` | 21.762 | **21.756** | 21.930 | 66.637 | 4561.185 |
| `binary_search` | 38.389 | **38.328** | 41.130 | 107.949 | 6473.562 |
| `sort_window` | 26.726 | **26.712** | 26.955 | 198.896 | 11761.358 |
| `bloom_filter` | **15.503** | 17.909 | 18.498 | 2837.911 | 7543.580 |
| `hash_join` | **27.162** | 28.185 | 29.427 | 3414.372 | 8382.934 |
| `sieve` | 20.689 | **20.308** | 20.533 | 67.798 | 3265.292 |
| `fib` | 29.900 | **29.827** | 30.091 | 132.883 | 1368.714 |
| `collatz` | 12.331 | **12.293** | 12.693 | 50.655 | 747.609 |
| `matmul` | 33.872 | **33.612** | 33.968 | 77.304 | 3154.841 |
| `json_parse` | **8.315** | 8.677 | 11.998 | 37.154 | 40.145 |
| `nbody` | 25.406 | 39.847 | **25.402** | 100.511 | 3099.560 |
| `chacha20` | **7.382** | 42.501 | 33.902 | n/a | n/a |
| `poly1305` | **11.937** | 31.976 | 21.354 | n/a | n/a |
| `blake2b` | **43.867** | 65.278 | 69.326 | n/a | n/a |
| `sha512` | **46.734** | 50.527 | 49.809 | n/a | n/a |
| `x25519` | **44.550** | 48.678 | 49.663 | n/a | n/a |

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
| _(floor: empty program)_ | _4.276_ | _110.509_ | _**114.785**_ | _64.004_ | _80.176_ | _58.282_ |
| `lcg` | 4.410 | 122.857 | **127.267** | 60.824 | 89.378 | 57.693 |
| `packet_classifier` | 4.604 | 123.593 | **128.197** | 61.238 | 91.963 | 57.226 |
| `ring_write` | 14.027 | 130.438 | **144.465** | 74.411 | 93.739 | 59.946 |
| `histogram_bins` | 14.009 | 130.857 | **144.866** | 73.087 | 111.817 | 67.965 |
| `prefix_scan` | 14.331 | 132.309 | **146.640** | 73.651 | 100.338 | 64.757 |
| `binary_search` | 14.199 | 129.754 | **143.953** | 73.724 | 96.096 | 65.006 |
| `sort_window` | 14.452 | 132.331 | **146.783** | 73.703 | 105.326 | 69.564 |
| `bloom_filter` | 14.627 | 131.538 | **146.165** | 73.970 | 101.905 | 64.768 |
| `hash_join` | 18.982 | 279.153 | **298.135** | 79.966 | 223.129 | 111.907 |
| `sieve` | 14.382 | 130.507 | **144.889** | 73.790 | 106.707 | 70.764 |
| `fib` | 4.691 | 123.212 | **127.903** | 62.690 | 92.464 | 59.774 |
| `collatz` | 4.833 | 130.111 | **134.944** | 64.184 | 95.461 | 60.519 |
| `matmul` | 15.852 | 132.461 | **148.313** | 75.630 | 109.775 | 79.670 |
| `json_parse` | 49.538 | 502.366 | **551.904** | 109.733 | 163.937 | 161.994 |
| `nbody` | 17.321 | 142.486 | **159.807** | 77.631 | 131.538 | 96.423 |
| `chacha20` | 57.586 | 841.290 | **898.876** | 116.888 | 143.967 | 106.950 |
| `poly1305` | 42.685 | 523.759 | **566.444** | 101.931 | 144.459 | 120.984 |
| `blake2b` | 37.989 | 389.776 | **427.765** | 97.722 | 150.255 | 117.710 |
| `sha512` | 37.901 | 488.170 | **526.071** | 97.861 | 141.050 | 101.712 |
| `x25519` | 37.935 | 846.530 | **884.465** | 97.148 | 1252.689 | 504.255 |

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
