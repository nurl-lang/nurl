# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-28T10:27:37Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366628 KiB |
| Commit | `6728666c74f887bd064f18562ef5ac26a128fba4` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/46134766127 |
| NURL | `v0.95.0-42-g6728666c7` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.1 (20ddd0171 2026-11-25) |
| Node | v24.22.3 |
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
| _(floor: empty program)_ | _2.923_ | _2.990_ | _3.151_ | _23.687_ | _12.446_ |
| `lcg` | 36.096 | **36.092** | 36.260 | 1478.383 | 4132.447 |
| `packet_classifier` | 51.339 | **51.198** | 51.348 | 128.266 | 3336.700 |
| `ring_write` | 39.015 | **38.825** | 38.997 | 63.250 | 5130.876 |
| `histogram_bins` | 36.571 | **36.528** | 36.673 | 63.327 | 4805.819 |
| `prefix_scan` | 20.753 | **20.738** | 20.977 | 57.849 | 3347.508 |
| `binary_search` | 34.308 | 33.913 | **30.463** | 91.126 | 4888.493 |
| `sort_window` | 25.281 | **25.072** | 25.230 | 129.460 | 8557.319 |
| `bloom_filter` | **15.384** | 16.299 | 17.880 | 2214.247 | 5604.039 |
| `hash_join` | 22.768 | **22.563** | 25.379 | 2664.646 | 5636.117 |
| `sieve` | **20.539** | 24.008 | 20.788 | 62.306 | 2518.776 |
| `fib` | 27.657 | 27.699 | **23.570** | 116.890 | 884.113 |
| `collatz` | 12.468 | **12.342** | 12.516 | 45.043 | 557.896 |
| `matmul` | **37.207** | 37.510 | 37.388 | 63.269 | 2414.815 |
| `json_parse` | **6.495** | 10.886 | 15.267 | 33.389 | 28.808 |
| `nbody` | **22.211** | 41.182 | 22.737 | 79.260 | 2485.731 |
| `safe_record_array` | 50.469 | **48.732** | 56.739 | n/a | n/a |
| `payload_state_machine` | 66.166 | 64.618 | **64.385** | n/a | n/a |
| `captured_closure_queue` | 78.257 | **75.216** | 88.849 | n/a | n/a |
| `dynamic_method_mix` | 128.853 | **101.724** | 125.223 | n/a | n/a |
| `csv_table_pipeline` | **70.792** | 81.433 | 73.790 | n/a | n/a |
| `chacha20` | **6.251** | 34.216 | 29.609 | n/a | n/a |
| `poly1305` | **12.598** | 20.009 | 20.257 | n/a | n/a |
| `blake2b` | **38.676** | 56.927 | 62.573 | n/a | n/a |
| `sha512` | 40.498 | **40.348** | 44.192 | n/a | n/a |
| `x25519` | **30.513** | 44.270 | 45.434 | n/a | n/a |

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
| _(floor: empty program)_ | _5.390_ | _63.126_ | _**68.516**_ | _27.773_ | _35.795_ | _49.291_ |
| `lcg` | 5.716 | 67.371 | **73.087** | 27.366 | 42.243 | 54.760 |
| `packet_classifier` | 5.811 | 68.512 | **74.323** | 27.809 | 43.204 | 54.545 |
| `ring_write` | 11.308 | 69.672 | **80.980** | 33.200 | 43.465 | 55.673 |
| `histogram_bins` | 11.597 | 71.213 | **82.810** | 33.581 | 60.907 | 62.057 |
| `prefix_scan` | 11.304 | 70.062 | **81.366** | 33.047 | 46.377 | 58.504 |
| `binary_search` | 11.653 | 69.523 | **81.176** | 33.757 | 44.552 | 59.800 |
| `sort_window` | 11.478 | 70.896 | **82.374** | 33.338 | 49.408 | 63.976 |
| `bloom_filter` | 11.893 | 70.842 | **82.735** | 33.831 | 48.129 | 60.584 |
| `hash_join` | 14.747 | 120.492 | **135.239** | 36.642 | 96.189 | 95.107 |
| `sieve` | 11.457 | 69.742 | **81.199** | 33.438 | 49.556 | 65.278 |
| `fib` | 6.004 | 67.251 | **73.255** | 27.811 | 42.493 | 55.003 |
| `collatz` | 6.059 | 68.765 | **74.824** | 27.720 | 42.888 | 55.080 |
| `matmul` | 12.010 | 69.722 | **81.732** | 33.849 | 51.052 | 71.386 |
| `json_parse` | 38.404 | 182.777 | **221.181** | 60.565 | 77.503 | 134.137 |
| `nbody` | 12.647 | 73.452 | **86.099** | 34.519 | 62.523 | 84.353 |
| `safe_record_array` | 14.282 | 152.072 | **166.354** | 36.422 | 52.734 | 74.724 |
| `payload_state_machine` | 22.263 | 124.189 | **146.452** | 44.082 | 53.931 | 78.626 |
| `captured_closure_queue` | 17.863 | 178.176 | **196.039** | 40.266 | 60.694 | 98.633 |
| `dynamic_method_mix` | 16.866 | 174.169 | **191.035** | 39.284 | 57.929 | 91.932 |
| `csv_table_pipeline` | 68.458 | 392.076 | **460.534** | 90.906 | 148.931 | 208.830 |
| `chacha20` | 53.368 | 358.888 | **412.256** | 75.818 | 68.644 | 93.692 |
| `poly1305` | 43.742 | 201.751 | **245.493** | 65.823 | 71.145 | 104.498 |
| `blake2b` | 28.844 | 170.595 | **199.439** | 51.059 | 68.594 | 100.995 |
| `sha512` | 27.481 | 239.436 | **266.917** | 49.437 | 68.453 | 89.544 |
| `x25519` | 40.648 | 834.105 | **874.753** | 62.873 | 735.859 | 395.895 |

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
| `safe_record_array` | `7272179836431339923` | identical across 3 languages |
| `payload_state_machine` | `7410019181044824385` | identical across 3 languages |
| `captured_closure_queue` | `1139091110298229923` | identical across 3 languages |
| `dynamic_method_mix` | `1376727108579200197` | identical across 3 languages |
| `csv_table_pipeline` | `4173891341820504351` | identical across 3 languages |
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
* `safe_record_array`, `payload_state_machine`, `captured_closure_queue`,
  `dynamic_method_mix` and `csv_table_pipeline` are NURL / C / Rust only.
  Each measures one language mechanism — by-value records in a checked
  Vec, payload-bearing enums and results, the closure ABI, trait-object
  dispatch, and the stdlib CSVTable parser with its zero-copy views — and
  is written in safe NURL (no `unsafe`). C spells closures and trait
  objects as the { code, environment } pairs they lower to, and carries
  the CSVTable layout by hand; see bench/README.md for what differs.
* Wall clock on a machine that was not quiesced drifts a few per cent
  between runs, and more on a shared CI runner. Compare deltas between
  runs of the same workflow, not absolutes across machines.
