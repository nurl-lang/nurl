# `compare/` — NURL CSV benchmarks

Reproducible head-to-head benchmarks for `stdlib/ext/csv.nu` against
Polars (Rust + Apache Arrow), Python's built-in `csv` module, and
(when present) any other comparator. The numbers in
[CSVROADMAP.md](CSVROADMAP.md) and the entries in
[HISTORY.md](HISTORY.md) all come from this directory.

## Quick start

```sh
# 1. one-time: create venv, install Polars
python3 -m venv .venv
.venv/bin/pip install polars

# 2. one-time: regenerate the deterministic 1 M-row fixture (~30 s, ~102 MB)
.venv/bin/python generate_data.py 1000000 test_data.csv
sha256sum test_data.csv
# expected: d00a0fd4509ea4a5c98ae4ff8c898a99a2abda8bbaf2a60e535d57aa611cec0b

# 3. bootstrap the compiler/toolchain
cd ..
zig build bootstrap

# 4. run the harness (builds compare/nurl_analysis, runs 5x each, appends HISTORY.md)
zig build bench-csv
```

## What's in here

| File                   | Purpose                                                   |
|------------------------|-----------------------------------------------------------|
| `CSVROADMAP.md`        | Phased plan to make `csv.nu` production-ready             |
| `HISTORY.md`           | Append-only bench log, one block per `zig build bench-csv` call |
| `PROFILE.md`           | `perf record/report` snapshots — top hot symbols          |
| `run_bench.sh`         | Thin compatibility wrapper around `zig build bench-csv -- ...` |
| `generate_data.py`     | Deterministic 1 M-row generator (seed `0xC0FFEE`)         |
| `nurl_analysis.nu`     | NURL pipeline: load → filter → sort → top-10 → write      |
| `polars_analysis.py`   | Same pipeline in Polars                                    |
| `sort_data.py`         | Vanilla Python `csv` module sort baseline                 |
| `test_quoting.nu`      | RFC 4180 quoting round-trip cases                          |
| `test_split.nu`        | Edge cases for the row scanner                             |

The fixture file `test_data.csv` is **not** committed — it is 102 MB.
Regenerate it locally; the harness checks the SHA on every run.

## Reproducibility checklist

Before pasting a comparison into a PR or commit:

1. Fixture SHA matches the value in `HISTORY.md` (otherwise the random
   data is different — comparisons across runs are meaningless).
2. The machine name appears in the `HISTORY.md` block. Bench numbers
   are not transferable across CPUs.
3. `zig build bench-csv` was run *at least* 5 times in succession; report
   the median, not the first run (which warms caches).
4. No other CPU-bound process was running. `pidstat 1` should show the
   harness as the dominant consumer.
5. CPU governor pinned to `performance` if you need < 3 % variance:

   ```sh
   sudo cpupower frequency-set -g performance
   ```

## Understanding the timings

`nurl_analysis` and `polars_analysis.py` print four stages:

| Stage    | What it measures                                          |
|----------|-----------------------------------------------------------|
| `load`   | parse the entire CSV into the implementation's table type |
| `filter` | retain rows where `val_float2 > 0` AND `text_words` contains `juliet` |
| `sort`   | sort filtered rows by `val_int` descending                |
| `write`  | write the top-10 to a fresh CSV                           |

NURL also reports a wall-clock `total` (sum of stages plus a tiny
print-out cost). Polars's `total` is the same.

## Adding a new comparator

If you add e.g. `pandas_analysis.py`, follow the existing output
contract so `zig build bench-csv` can parse it:

```
Loaded N rows x M cols in <ms>ms
Filtered to N rows in <ms>ms
Sorted (val_int desc) in <ms>ms
Top-10 written to <path> in <ms>ms

Total: <ms>ms
```

The harness greps lines starting with `Loaded `, `Filtered`, `Sorted `,
`Top-10 `, `Total: `; ms is the last whitespace-separated token on the
line, optionally suffixed `ms`.

## Profiling

```sh
# 1. build with debug info (so symbol names survive)
cd .. && zig build nurl -- -O2 -g compare/nurl_analysis.nu compare/nurl_analysis
cd compare

# 2. record + report
perf record -g --call-graph=dwarf ./nurl_analysis > /dev/null
perf report --stdio --no-children | head -60
```

Capture the top-10 self-time symbols into `PROFILE.md` so we can
discuss specific lines instead of vibes.
