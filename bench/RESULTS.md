# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-10-31T02:10:17Z` by `bench/bench.sh`. **Do not edit by hand** — the next
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
| Commit | `156134587d5380f1b27a71cd1630e9487b77962b` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/41158304966 |
| NURL | `v0.81.0-36-g15613458` |
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
| _(floor: empty program)_ | _3.404_ | _3.319_ | _3.563_ | _27.209_ | _15.025_ |
| `lcg` | 41.138 | **41.033** | 41.315 | 1794.477 | 5174.370 |
| `packet_classifier` | **58.256** | 58.371 | 58.423 | 168.541 | 4050.223 |
| `ring_write` | 44.520 | **44.335** | 44.503 | 71.973 | 6907.472 |
| `histogram_bins` | **41.597** | 42.691 | 42.927 | 71.413 | 5632.205 |
| `prefix_scan` | 23.848 | **23.842** | 23.954 | 68.709 | 4123.933 |
| `binary_search` | 41.765 | **40.269** | 42.891 | 109.994 | 5941.231 |
| `sort_window` | 28.496 | **28.474** | 28.745 | 197.468 | 11902.150 |
| `bloom_filter` | **18.517** | 19.766 | 20.211 | 2930.034 | 7041.055 |
| `hash_join` | 28.900 | **28.869** | 31.588 | 3460.184 | 7608.370 |
| `sieve` | 26.339 | 26.218 | **26.147** | 74.297 | 3145.640 |
| `fib` | **27.485** | 32.016 | 32.081 | 137.292 | 1097.522 |
| `collatz` | 14.480 | **14.301** | 14.600 | 54.441 | 683.790 |
| `matmul` | **36.121** | 36.218 | 36.269 | 77.239 | 3098.775 |
| `json_parse` | **10.259** | 13.098 | 18.608 | 40.242 | 36.735 |
| `nbody` | **25.937** | 41.949 | 27.210 | 102.866 | 2973.740 |
| `chacha20` | **9.370** | 44.637 | 35.926 | n/a | n/a |
| `poly1305` | **13.363** | 33.767 | 23.094 | n/a | n/a |
| `blake2b` | **46.309** | 66.644 | 71.450 | n/a | n/a |
| `sha512` | **49.756** | 49.899 | 52.234 | n/a | n/a |
| `x25519` | **33.470** | 51.159 | 51.396 | n/a | n/a |

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
| _(floor: empty program)_ | _6.513_ | _119.809_ | _**126.322**_ | _63.653_ | _80.842_ | _64.787_ |
| `lcg` | 6.690 | 129.781 | **136.471** | 64.337 | 91.066 | 72.164 |
| `packet_classifier` | 6.778 | 130.983 | **137.761** | 65.457 | 95.795 | 74.013 |
| `ring_write` | 17.163 | 132.890 | **150.053** | 76.248 | 94.278 | 73.328 |
| `histogram_bins` | 17.811 | 137.905 | **155.716** | 77.571 | 139.738 | 82.448 |
| `prefix_scan` | 17.720 | 139.527 | **157.247** | 78.464 | 102.435 | 77.638 |
| `binary_search` | 17.487 | 150.537 | **168.024** | 77.292 | 97.143 | 80.289 |
| `sort_window` | 17.517 | 137.399 | **154.916** | 74.337 | 104.818 | 83.514 |
| `bloom_filter` | 18.172 | 137.357 | **155.529** | 76.728 | 103.515 | 79.440 |
| `hash_join` | 21.565 | 271.911 | **293.476** | 80.323 | 222.680 | 127.170 |
| `sieve` | 17.635 | 135.387 | **153.022** | 76.217 | 108.255 | 85.824 |
| `fib` | 6.924 | 131.373 | **138.297** | 64.723 | 92.654 | 73.721 |
| `collatz` | 7.278 | 138.586 | **145.864** | 68.484 | 95.274 | 73.368 |
| `matmul` | 18.365 | 138.836 | **157.201** | 78.482 | 112.116 | 96.110 |
| `json_parse` | 53.926 | 469.307 | **523.233** | 116.451 | 165.391 | 177.745 |
| `nbody` | 19.763 | 141.572 | **161.335** | 78.131 | 131.110 | 114.696 |
| `chacha20` | 59.693 | 793.366 | **853.059** | 120.641 | 148.432 | 124.060 |
| `poly1305` | 46.452 | 515.896 | **562.348** | 106.393 | 150.241 | 137.955 |
| `blake2b` | 41.300 | 341.646 | **382.946** | 101.331 | 148.875 | 134.842 |
| `sha512` | 41.979 | 465.337 | **507.316** | 104.183 | 144.692 | 119.410 |
| `x25519` | 56.401 | 1554.751 | **1611.152** | 117.523 | 1247.824 | 518.152 |

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
