# Benchmark results — NURL vs C vs Rust vs Node vs Python

Generated `2026-11-21T09:52:22Z` by `bench/bench.sh`. **Do not edit by hand** — the next
run overwrites it. The machine-readable form of this same run is
[`results/latest.json`](results/latest.json), which is what the landing
page renders its table from.

## Environment

| Item | Value |
|---|---|
| Host | `GitHub Actions ubuntu-latest runner` |
| Kernel | `Linux 7.0.0-1020-azure x86_64` |
| CPU | AMD EPYC 7763 64-Core Processor (4 logical cores) |
| Memory | 16366628 KiB |
| Commit | `cb36a4ffbe6f06afed9af427e3b51a5a0f854c37` |
| CI run | https://github.com/nurl-lang/nurl/actions/runs/44891025868 |
| NURL | `v0.92.1-134-gcb36a4ff` |
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
| _(floor: empty program)_ | _3.541_ | _3.365_ | _3.600_ | _26.546_ | _14.970_ |
| `lcg` | 41.318 | **41.080** | 41.554 | 1824.771 | 4967.998 |
| `packet_classifier` | 58.822 | 58.635 | **58.629** | 167.449 | 4008.950 |
| `ring_write` | 44.384 | **44.281** | 44.418 | 70.991 | 6129.902 |
| `histogram_bins` | 41.567 | 42.597 | **41.348** | 71.792 | 5618.865 |
| `prefix_scan` | **23.493** | 23.569 | 23.763 | 69.398 | 4310.051 |
| `binary_search` | 41.799 | 41.681 | **37.792** | 110.472 | 6256.748 |
| `sort_window` | 28.803 | **28.607** | 28.839 | 198.883 | 12021.699 |
| `bloom_filter` | **17.780** | 19.335 | 20.241 | 2767.968 | 7295.144 |
| `hash_join` | **28.516** | 28.836 | 31.448 | 3334.905 | 7678.153 |
| `sieve` | 23.938 | 27.604 | **23.653** | 71.995 | 3103.677 |
| `fib` | 31.558 | 31.658 | **27.372** | 134.604 | 1126.554 |
| `collatz` | 14.173 | **14.094** | 14.313 | 53.002 | 698.589 |
| `matmul` | 35.720 | 35.806 | **35.641** | 75.094 | 2914.175 |
| `json_parse` | **8.241** | 13.222 | 18.383 | 39.785 | 38.338 |
| `nbody` | **26.134** | 48.561 | 27.121 | 102.638 | 3065.595 |
| `safe_record_array` | 58.574 | **56.910** | 65.199 | n/a | n/a |
| `payload_state_machine` | 76.838 | **72.673** | 75.093 | n/a | n/a |
| `captured_closure_queue` | 90.413 | **87.049** | 103.389 | n/a | n/a |
| `dynamic_method_mix` | 121.259 | **117.335** | 149.364 | n/a | n/a |
| `csv_table_pipeline` | **83.718** | 93.473 | 85.701 | n/a | n/a |
| `chacha20` | **9.371** | 40.592 | 33.191 | n/a | n/a |
| `poly1305` | **13.460** | 22.824 | 23.068 | n/a | n/a |
| `blake2b` | **43.107** | 66.445 | 71.134 | n/a | n/a |
| `sha512` | **48.205** | 48.736 | 51.238 | n/a | n/a |
| `x25519` | **35.465** | 50.673 | 52.037 | n/a | n/a |

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
| _(floor: empty program)_ | _7.628_ | _73.301_ | _**80.929**_ | _32.495_ | _41.194_ | _66.995_ |
| `lcg` | 7.189 | 77.741 | **84.930** | 31.366 | 47.253 | 71.675 |
| `packet_classifier` | 7.231 | 77.328 | **84.559** | 32.781 | 48.045 | 72.184 |
| `ring_write` | 14.668 | 82.905 | **97.573** | 40.004 | 50.291 | 76.766 |
| `histogram_bins` | 14.603 | 82.218 | **96.821** | 38.987 | 71.129 | 80.391 |
| `prefix_scan` | 14.642 | 82.536 | **97.178** | 39.480 | 52.864 | 78.456 |
| `binary_search` | 14.770 | 82.147 | **96.917** | 39.431 | 50.260 | 77.400 |
| `sort_window` | 15.158 | 85.269 | **100.427** | 40.387 | 58.149 | 87.002 |
| `bloom_filter` | 15.242 | 81.738 | **96.980** | 39.431 | 53.925 | 79.130 |
| `hash_join` | 19.194 | 146.213 | **165.407** | 44.180 | 117.466 | 126.193 |
| `sieve` | 14.473 | 82.027 | **96.500** | 39.092 | 55.981 | 84.724 |
| `fib` | 7.274 | 76.665 | **83.939** | 31.668 | 46.623 | 71.999 |
| `collatz` | 7.551 | 79.756 | **87.307** | 31.669 | 47.463 | 71.646 |
| `matmul` | 14.896 | 81.608 | **96.504** | 39.710 | 58.150 | 95.745 |
| `json_parse` | 49.991 | 211.392 | **261.383** | 75.664 | 91.970 | 173.855 |
| `nbody` | 16.776 | 86.603 | **103.379** | 41.582 | 73.721 | 109.086 |
| `safe_record_array` | 18.622 | 180.167 | **198.789** | 43.058 | 57.704 | 97.718 |
| `payload_state_machine` | 28.049 | 146.884 | **174.933** | 52.216 | 61.294 | 102.690 |
| `captured_closure_queue` | 22.440 | 213.570 | **236.010** | 47.121 | 71.089 | 127.628 |
| `dynamic_method_mix` | 21.509 | 209.897 | **231.406** | 46.079 | 66.360 | 118.621 |
| `csv_table_pipeline` | 87.786 | 467.065 | **554.851** | 113.380 | 180.477 | 265.735 |
| `chacha20` | 70.121 | 405.589 | **475.710** | 95.039 | 78.811 | 120.828 |
| `poly1305` | 58.303 | 245.172 | **303.475** | 82.896 | 82.808 | 134.811 |
| `blake2b` | 36.741 | 203.486 | **240.227** | 61.180 | 78.970 | 130.543 |
| `sha512` | 35.106 | 294.189 | **329.295** | 59.958 | 78.506 | 115.732 |
| `x25519` | 52.785 | 1044.309 | **1097.094** | 77.375 | 944.581 | 510.375 |

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
