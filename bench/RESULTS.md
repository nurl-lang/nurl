# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-27T10:55:11Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 9V74 80-Core Processor (4 logical cores) |
| Memory | 16366632 KiB |
| Commit | `85ffe29e7b2fb1966b803d062c5a4095b2bb2402` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/45985271811 |
| NURL | `v0.95.0-13-g85ffe29e7` |
| C | clang version 23.1.5 (https://github.com/llvm/llvm-project 392dfff97d29b59d77e5cac6d4b6ef2585fe7117) |
| Rust | rustc 1.100.0 (0ef1bc386 2026-11-09) |
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
| _(floor: empty program)_ | _2.915_ | _2.871_ | _3.048_ | _22.388_ | _12.161_ |
| `lcg` | 36.141 | **36.010** | 36.153 | 1476.228 | 4063.740 |
| `packet_classifier` | 51.212 | **51.138** | 51.377 | 126.682 | 3407.998 |
| `ring_write` | 38.773 | **38.723** | 38.928 | 60.854 | 4969.084 |
| `histogram_bins` | 36.409 | **36.361** | 36.527 | 63.315 | 4479.685 |
| `prefix_scan` | 20.758 | **20.681** | 20.829 | 56.852 | 3294.693 |
| `binary_search` | 34.025 | 33.989 | **30.310** | 90.123 | 4969.024 |
| `sort_window` | 25.082 | **24.999** | 25.128 | 128.441 | 8310.670 |
| `bloom_filter` | **15.200** | 16.207 | 17.722 | 2185.082 | 5888.104 |
| `hash_join` | 22.573 | **22.484** | 25.105 | 2652.410 | 5823.875 |
| `sieve` | **20.217** | 23.324 | 20.401 | 61.147 | 2478.033 |
| `fib` | 27.482 | 27.459 | **23.574** | 117.115 | 861.738 |
| `collatz` | 12.335 | **12.318** | 12.462 | 44.288 | 532.314 |
| `matmul` | 37.895 | 37.961 | **37.431** | 61.502 | 2436.033 |
| `json_parse` | **6.434** | 10.739 | 15.035 | 31.862 | 29.507 |
| `nbody` | **21.913** | 41.007 | 22.583 | 77.477 | 2484.677 |
| `safe_record_array` | 50.445 | **48.641** | 56.492 | n/a | n/a |
| `payload_state_machine` | 66.182 | 64.639 | **64.390** | n/a | n/a |
| `captured_closure_queue` | 78.218 | **75.187** | 88.552 | n/a | n/a |
| `dynamic_method_mix` | 126.722 | **101.789** | 125.166 | n/a | n/a |
| `csv_table_pipeline` | **70.421** | 79.563 | 72.101 | n/a | n/a |
| `chacha20` | **6.267** | 34.157 | 29.388 | n/a | n/a |
| `poly1305` | **12.527** | 20.047 | 20.218 | n/a | n/a |
| `blake2b` | **38.597** | 56.785 | 63.027 | n/a | n/a |
| `sha512` | 40.333 | **40.277** | 44.102 | n/a | n/a |
| `x25519` | **30.436** | 44.368 | 45.089 | n/a | n/a |

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
| _(floor: empty program)_ | _5.346_ | _61.199_ | _**66.545**_ | _26.530_ | _34.208_ | _59.414_ |
| `lcg` | 5.522 | 65.095 | **70.617** | 26.743 | 40.290 | 61.896 |
| `packet_classifier` | 5.575 | 66.654 | **72.229** | 26.897 | 41.794 | 62.992 |
| `ring_write` | 11.064 | 67.484 | **78.548** | 32.478 | 42.422 | 64.639 |
| `histogram_bins` | 11.064 | 68.434 | **79.498** | 32.355 | 59.352 | 70.187 |
| `prefix_scan` | 11.066 | 68.428 | **79.494** | 32.501 | 44.799 | 67.483 |
| `binary_search` | 11.223 | 67.780 | **79.003** | 32.925 | 42.891 | 69.041 |
| `sort_window` | 11.294 | 69.210 | **80.504** | 32.692 | 48.391 | 72.799 |
| `bloom_filter` | 11.697 | 69.736 | **81.433** | 33.268 | 46.629 | 68.927 |
| `hash_join` | 14.462 | 117.677 | **132.139** | 35.759 | 95.103 | 105.076 |
| `sieve` | 11.343 | 67.679 | **79.022** | 32.922 | 48.536 | 73.992 |
| `fib` | 5.760 | 66.158 | **71.918** | 27.199 | 42.173 | 63.603 |
| `collatz` | 5.903 | 66.946 | **72.849** | 27.217 | 41.539 | 63.628 |
| `matmul` | 11.644 | 68.509 | **80.153** | 32.981 | 50.165 | 81.548 |
| `json_parse` | 37.289 | 180.442 | **217.731** | 58.944 | 75.477 | 145.083 |
| `nbody` | 12.688 | 72.119 | **84.807** | 34.244 | 60.756 | 93.079 |
| `safe_record_array` | 14.014 | 149.273 | **163.287** | 35.672 | 50.773 | 85.173 |
| `payload_state_machine` | 21.367 | 122.936 | **144.303** | 42.701 | 53.054 | 88.370 |
| `captured_closure_queue` | 17.659 | 175.428 | **193.087** | 39.172 | 59.600 | 109.453 |
| `dynamic_method_mix` | 17.150 | 171.917 | **189.067** | 38.956 | 56.611 | 101.740 |
| `csv_table_pipeline` | 66.624 | 386.909 | **453.533** | 88.687 | 146.987 | 219.902 |
| `chacha20` | 51.952 | 356.158 | **408.110** | 73.724 | 67.225 | 111.726 |
| `poly1305` | 42.851 | 200.764 | **243.615** | 64.614 | 69.886 | 114.124 |
| `blake2b` | 28.019 | 168.103 | **196.122** | 49.731 | 67.677 | 111.316 |
| `sha512` | 26.935 | 236.820 | **263.755** | 48.635 | 67.112 | 99.674 |
| `x25519` | 39.174 | 819.443 | **858.617** | 60.794 | 733.184 | 406.726 |

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
