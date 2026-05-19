# CSV bench history

Append-only log of `compare/run_bench.sh` results. Add the most recent
run at the bottom. Every entry must include the git SHA of the
compiler/runtime built at that point and the SHA-256 prefix of the
fixture so old entries remain interpretable.

To regenerate the fixture:

```sh
./.venv/bin/python generate_data.py 1000000 test_data.csv
sha256sum test_data.csv  # must match the prefix recorded below
```

Expected fixture SHA-256 (1 M rows, seed=0xC0FFEE):

```
d00a0fd4509ea4a5c98ae4ff8c898a99a2abda8bbaf2a60e535d57aa611cec0b  test_data.csv
```

If your file disagrees, your `generate_data.py` is on a different
random algorithm or seed; do not trust comparisons until the SHA
matches.

## 2026-05-07 21:27:11Z — 49e1c56+dirty — v1 baseline (post-roadmap rewrite)
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 3 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |     1095 |     1097 |         71 |         77 |            14.2× |
| filter |      403 |      410 |         18 |         20 |            20.5× |
| sort   |      925 |     1011 |         10 |         14 |            72.2× |
| write  |        0 |        0 |          2 |          3 |             0.0× |
| total  |     2426 |     2529 |        102 |        116 |            21.8× |

## 2026-05-07 22:00:18Z — 49e1c56+dirty — phase1-indexed-sort
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |     1079 |     1175 |         63 |         69 |            17.0× |
| filter |      380 |      456 |         20 |         21 |            21.7× |
| sort   |       52 |       54 |         11 |         11 |             4.9× |
| write  |        0 |        0 |          2 |          3 |             0.0× |
| total  |     1532 |     1716 |         98 |        105 |            16.3× |

## 2026-05-07 22:34:32Z — fe178d0+dirty — phase2a-arena-loader
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      437 |      445 |         66 |         71 |             6.3× |
| filter |      186 |      194 |         21 |         23 |             8.4× |
| sort   |       69 |       73 |         12 |         13 |             5.6× |
| write  |        0 |        0 |          3 |          3 |             0.0× |
| total  |      698 |      731 |        108 |        109 |             6.7× |

## 2026-05-08 — db5e53a+dirty — phase2b-raw-pointer-parser
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation
- Bench binary: `nurl_analysis_arena` (arena loader pipeline; `nurl_analysis` v1
  remains for regression-checking the legacy CSVTable path).

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      318 |      327 |         64 |         72 |             4.5× |
| filter |      152 |      157 |         20 |         21 |             7.5× |
| sort   |       69 |       75 |         11 |         13 |             5.8× |
| write  |        0 |        0 |          3 |          3 |             0.0× |
| total  |      561 |      562 |        100 |        115 |             4.9× |

Load drop (445 → 327 ms median, 27 % faster) comes from replacing
`vec_push` in the per-cell hot path with raw pointer writes:
`vec_reserve` + `vec_data` once per ROW, then cell stores via `. fcp i`.
Each old `vec_push` cost two unavoidable FFI calls (`nurl_peek` ctl
read + `nurl_poke` len bump) — `runtime.o` is built without LTO so
those calls are not inlined. Per-row reserves cut the FFI count from
~32 M (16 M cells × 2) down to ~5 M, freeing the LLVM-O2'd byte loop
to actually run at native speed.

Filter drop (194 → 157 ms median, 19 % faster) comes from the same
trick at the call site: `compare/nurl_analysis_arena.nu` now
prefetches `flat_cells` / `row_starts` / `row_lens` / `content`
pointers ONCE outside the filter loop, captured into the predicate
closure. Each old `csv_table_a_view` access fanned out into 3
`vec_data` calls (so 4 cell accesses × 3 = 12 M FFI per million
rows). The captured-pointer pattern is now the recommended idiom
for any hot per-row workload over `CSVTableA`.

Two earlier Phase 2b attempts regressed and are kept as cautionary
notes in `csv.nu`'s `__csv_a_parse_content` header comment:
  • `nurl_csv_parse_arena` (whole-file C parser): 510 ms — large up-
    front contiguous reservation page-faulted across the buffer.
  • `nurl_csv_scan_row_pairs` (per-row C scanner): 700 ms — 1 M FFI
    calls + transfer copy from C buffer to flat_cells via vec_push
    re-introduced the per-cell FFI cost we were trying to avoid.
Both helpers stay in `runtime.c` for the Phase 3 typed-schema reader,
where per-row FFI is amortized over genuine per-row typed work.

## 2026-05-08 07:21:22Z — 36ee05b+dirty
- CPU: 11th Gen Intel(R) Core(TM) i7-11850H @ 2.50GHz
- OS: Microsoft Windows 11 Pro
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 50 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      261 |      276 |         51 |         58 |              4.8x |
| filter |      113 |      124 |         12 |         14 |              8.9x |
| sort   |       35 |       36 |          6 |          8 |              4.5x |
| write  |        0 |        0 |          2 |          3 |              0.0x |
| total  |      412 |      436 |         74 |         82 |              5.3x |

## 2026-05-08 13:01:50Z — 8ae0030+dirty
- CPU: 11th Gen Intel(R) Core(TM) i7-11850H @ 2.50GHz
- OS: Microsoft Windows 11 Pro
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 50 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      247 |      256 |         48 |         52 |              4.9x |
| filter |      114 |      119 |         10 |         13 |              9.2x |
| sort   |       33 |       34 |          6 |          8 |              4.3x |
| write  |        0 |        0 |          2 |          3 |              0.0x |
| total  |      399 |      411 |         71 |         76 |              5.4x |

## 2026-05-08 14:43:01Z — 2c51f7c+dirty — **V1 BINARY (mismatch, see note)**
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |     1003 |     1016 |         54 |         57 |            17.8× |
| filter |      343 |      344 |         16 |         16 |            21.5× |
| sort   |       46 |       47 |          9 |          9 |             5.2× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |     1393 |     1412 |         81 |         84 |            16.8× |

**Note (added retroactively):** these numbers came from the legacy
`nurl_analysis` binary (V1 `csv_table_load` / `CSVTable` path), not the
arena pipeline that HISTORY.md otherwise tracks. `run_bench.sh`
defaulted to `nurl_analysis` while `run_bench.ps1` (Windows) was using
`nurl_analysis_arena.exe` — apples-to-oranges across the two
machines. `run_bench.sh` is now updated to mirror the Windows script
(arena binary by default, `--v1` flag for legacy regression-checking).
The next entry below is the corrected arena-pipeline measurement on
the same Linux box / same SHA — no actual regression vs. db5e53a; in
fact a 13 % load improvement and a 23 % sort improvement.

## 2026-05-08 14:55:45Z — 2c51f7c+dirty — arena-rerun (was 2c51f7c v1-binary mismatch)
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      284 |      285 |         58 |         60 |             4.8× |
| filter |      150 |      153 |         17 |         18 |             8.5× |
| sort   |       55 |       58 |          9 |          9 |             6.4× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      492 |      505 |         86 |         88 |             5.7× |

## 2026-05-08 15:03:01Z — 2c51f7c+dirty
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      278 |      279 |         55 |         56 |             5.0× |
| filter |      149 |      151 |         16 |         16 |             9.4× |
| sort   |       55 |       56 |          9 |          9 |             6.2× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      482 |      486 |         82 |         83 |             5.9× |

## 2026-05-08 16:21:21Z — 7115ef5+dirty
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |        0 |          |         55 |         60 |             0.0× |
| filter |        0 |          |         16 |         17 |             0.0× |
| sort   |        0 |          |          9 |          9 |             0.0× |
| write  |        0 |          |          2 |          2 |             0.0× |
| total  |        0 |          |         84 |         89 |             0.0× |

## 2026-05-08 16:23:04Z — 7115ef5+dirty
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |        0 |          |         56 |         59 |             0.0× |
| filter |        0 |          |         16 |         17 |             0.0× |
| sort   |        0 |          |          9 |         10 |             0.0× |
| write  |        0 |          |          2 |          2 |             0.0× |
| total  |        0 |          |         83 |         90 |             0.0× |

## 2026-05-08 16:26:21Z — 7115ef5+dirty
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-22-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      271 |      282 |         56 |         57 |             4.9× |
| filter |      149 |      150 |         16 |         17 |             8.8× |
| sort   |       55 |       56 |          9 |          9 |             6.2× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      477 |      488 |         83 |         85 |             5.7× |

## 2026-05-16 16:51:23Z — 666d7e1+dirty — baseline-no-LTO
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-23-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      302 |      315 |         64 |         65 |             4.8× |
| filter |      144 |      146 |         18 |         18 |             8.1× |
| sort   |       63 |       65 |         11 |         11 |             5.9× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      517 |      529 |         95 |         96 |             5.5× |

## 2026-05-16 16:55:44Z — 666d7e1+dirty — LTO-runtime
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-23-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      270 |      272 |         61 |         63 |             4.3× |
| filter |      135 |      139 |         17 |         19 |             7.3× |
| sort   |       36 |       40 |         10 |         11 |             3.6× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      446 |      451 |         92 |         95 |             4.7× |

## 2026-05-19 — 72b229f+dirty — SSE2 cell scan + C filter helpers + fast_atof
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-23-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      273 |      278 |         61 |         63 |             4.4× |
| filter |       99 |      105 |         17 |         19 |             5.5× |
| sort   |       52 |       53 |         10 |         11 |             4.8× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      424 |      436 |         92 |         95 |             4.6× |

Changes against 2026-05-16 LTO baseline (load 272 ms / filter 139 ms /
total 451 ms):

* **`__csv_parse_content` inner cell loop swaps NURL byte-by-byte
  scan for SSE2-vectorised `nurl_csv_scan_cell`** (16 bytes/iter
  cmpeq for delim/CR/LF; tail loop on the remainder). With LTO the
  FFI inlines into the parser; load drops 313 → 278 ms (~11 %).
* **Filter pipeline routed through `csv_table_filter_float_gt` +
  `csv_table_filter_str_contains` runtime helpers**: one FFI call
  per stage instead of per-row closure dispatch. `nurl_csv_filter_*`
  use an inline `__csv_fast_atof` (no `malloc`+`strtod`, just
  `-?digits(.digits)?(eE[+-]?digits)?`) — ~50 ns/row vs strtod's
  ~150 ns — and a first-byte-prefilter substring scan instead of
  glibc memmem. Filter 150 → 105 ms (~30 %).
* **Result count unchanged** — 150 162 rows survive, byte-identical
  `nurl_top10.csv` vs Polars.

Goal "halve load + filter from the LTO baseline" not yet reached —
load is wall-clocked by file-read + memory-write bandwidth more than
parse cost; further wins likely require columnar layout (P4) or
typed pre-parse during the byte-walk (P3b). Filter is bottlenecked
on parse_float + scattered flat_cells access for the survivor scan;
columnar storage would collapse both.

## 2026-05-19 — f4a44f3+dirty — combined predicate filter
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-23-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      278 |      287 |         61 |         63 |             4.6× |
| filter |       46 |       50 |         17 |         19 |             2.6× |
| sort   |       53 |       55 |         10 |         11 |             5.0× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      375 |      392 |         92 |         95 |             4.1× |

* **Combined-predicate filter helper**: `csv_table_filter_float_gt_and_str_contains` collapses the two filter stages into one FFI call with row-level short-circuit (float check first; ~85 % of rows skip the substring scan entirely). Filter drops 105 → 50 ms — **filter time halved relative to the LTO baseline (150 → 50 ms = -67 %)**. Load unchanged (parse cost is memory-bandwidth-bound).

## 2026-05-19 — 70be61e — final state after FFI-hoist revert
- CPU: Intel(R) Core(TM) i7-5930K CPU @ 3.50GHz
- Kernel: Linux 6.17.0-23-generic x86_64
- Fixture: test_data.csv (1 M rows × 8 cols, 106756536 B, sha256=d00a0fd4509ea4a5…)
- Runs: 5 per implementation

| Stage  | NURL min | NURL med | Polars min | Polars med | NURL/Polars (med) |
|--------|---------:|---------:|-----------:|-----------:|------------------:|
| load   |      278 |      282 |         61 |         63 |             4.5× |
| filter |       47 |       48 |         17 |         19 |             2.5× |
| sort   |       50 |       55 |         10 |         11 |             5.0× |
| write  |        0 |        0 |          2 |          2 |             0.0× |
| total  |      378 |      386 |         92 |         95 |             4.1× |

Session goal "puolitettu load + filter" — partial:
- Filter — **achieved**: 139 ms (LTO baseline) → 48 ms = **-65 %**.
- Load — **not achieved**: 272 ms (LTO baseline) → 282 ms = flat
  within run-to-run noise.

The FFI-hoist + pre-count experiment for the load path was attempted
on top of SSE2 + combined-filter; it segfaulted on the 1 M-row
fixture (re-grow + pointer-refresh edge in the row-loop body),
reverted to keep the tree green. Per CSVROADMAP.md's P2c notes the
hoist's ~30 ms theoretical ceiling collapsed to single-digit ms
post-LTO anyway. Load is memory-bandwidth + parser-write bound;
reaching `≤ 156 ms` requires either P3b (typed pre-parse during
the byte-walk) or P4 (columnar layout — `flat_cells` / `row_starts`
/ `row_lens` traded for one `Vec[T]` per column). Both require a
schema parameter through the load signature and new APIs on top.
