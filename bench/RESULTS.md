# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T00:56:59Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1017-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366644 KiB |
| Commit | `cc500c7b1658a7844046e271d6ef80268c5d6558` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41152359656 |
| NURL | `v0.81.0-30-gcc500c7b` |
| C | Ubuntu clang version 21.1.8 (6ubuntu1) |
| Rust | rustc 1.99.1 (58cf8f9c3 2026-10-13) |
| Node | v24.22.1 |
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
| _(floor: empty program)_ | _3.479_ | _3.549_ | _3.741_ | _30.050_ | _16.694_ |
| `lcg` | 41.743 | **41.690** | 41.922 | 1803.741 | 4915.726 |
| `packet_classifier` | 58.853 | **58.776** | 58.998 | 169.221 | 3982.860 |
| `ring_write` | 45.039 | **44.971** | 45.122 | 72.883 | 6134.152 |
| `histogram_bins` | **42.112** | 43.246 | 43.662 | 72.314 | 5641.322 |
| `prefix_scan` | **24.002** | 24.025 | 24.165 | 71.017 | 4067.976 |
| `binary_search` | 42.076 | **40.787** | 43.383 | 111.421 | 6085.127 |
| `sort_window` | **29.294** | **29.294** | 29.516 | 200.593 | 12087.191 |
| `bloom_filter` | **18.994** | 20.224 | 20.690 | 2861.071 | 7351.138 |
| `hash_join` | 29.374 | **28.869** | 31.898 | 3407.747 | 7559.987 |
| `sieve` | 27.844 | **27.682** | 27.687 | 77.797 | 3050.197 |
| `fib` | **27.694** | 32.317 | 32.535 | 138.905 | 1122.746 |
| `collatz` | **14.673** | 14.780 | 15.125 | 57.133 | 692.805 |
| `matmul` | **36.501** | 36.576 | 36.617 | 77.826 | 3197.970 |
| `json_parse` | **11.071** | 13.868 | 19.068 | 42.210 | 38.947 |
| `nbody` | **26.724** | 42.509 | 28.147 | 108.850 | 2956.488 |
| `chacha20` | **9.644** | 43.971 | 36.414 | n/a | n/a |
| `poly1305` | **13.974** | 34.356 | 23.686 | n/a | n/a |
| `blake2b` | **46.690** | 67.181 | 71.725 | n/a | n/a |
| `sha512` | **49.965** | 50.096 | 51.999 | n/a | n/a |
| `x25519` | **34.094** | 51.405 | 51.658 | n/a | n/a |

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
| _(floor: empty program)_ | _7.123_ | _123.702_ | _**130.825**_ | _70.849_ | _85.479_ | _65.843_ |
| `lcg` | 7.337 | 131.534 | **138.871** | 68.046 | 96.804 | 73.818 |
| `packet_classifier` | 7.057 | 132.015 | **139.072** | 67.812 | 96.272 | 75.680 |
| `ring_write` | 17.987 | 136.123 | **154.110** | 79.491 | 99.773 | 75.688 |
| `histogram_bins` | 17.928 | 137.537 | **155.465** | 78.699 | 142.331 | 83.615 |
| `prefix_scan` | 17.879 | 135.291 | **153.170** | 78.817 | 104.305 | 80.268 |
| `binary_search` | 17.874 | 131.517 | **149.391** | 76.718 | 97.033 | 82.339 |
| `sort_window` | 18.136 | 136.372 | **154.508** | 78.385 | 108.446 | 89.085 |
| `bloom_filter` | 18.894 | 139.039 | **157.933** | 78.718 | 109.035 | 82.075 |
| `hash_join` | 22.470 | 274.064 | **296.534** | 81.908 | 224.213 | 130.260 |
| `sieve` | 18.033 | 133.478 | **151.511** | 78.729 | 107.831 | 89.607 |
| `fib` | 7.112 | 130.275 | **137.387** | 67.753 | 94.768 | 76.820 |
| `collatz` | 7.351 | 134.793 | **142.144** | 68.837 | 99.394 | 76.439 |
| `matmul` | 20.253 | 139.708 | **159.961** | 82.836 | 117.174 | 103.328 |
| `json_parse` | 54.124 | 469.640 | **523.764** | 115.838 | 165.847 | 186.067 |
| `nbody` | 21.097 | 142.401 | **163.498** | 82.448 | 134.038 | 115.914 |
| `chacha20` | 61.561 | 806.753 | **868.314** | 123.988 | 149.815 | 136.698 |
| `poly1305` | 48.000 | 529.647 | **577.647** | 110.219 | 153.091 | 143.113 |
| `blake2b` | 42.997 | 346.412 | **389.409** | 105.624 | 152.007 | 143.658 |
| `sha512` | 42.469 | 468.201 | **510.670** | 105.243 | 148.106 | 136.292 |
| `x25519` | 57.427 | 1578.920 | **1636.347** | 119.787 | 1270.532 | 519.158 |

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
