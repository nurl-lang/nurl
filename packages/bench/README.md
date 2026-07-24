# bench

Reproduce NURL's performance claims on your own machine — a runnable benchmark
suite, not a number in a README.

```
$ nurlpkg install bench
$ bench
NURL benchmark suite — pure-NURL throughput on this machine

  sha256                88 MB/s    (11829677 ns/op, 16390 allocs/op)
  json parse           147 MB/s    (517785 ns/op, 9602 allocs/op)
  sort i64              18 M/s     (2697244 ns/op, 1 allocs/op)
  cbor decode           20 MB/s    (293288 ns/op, 2002 allocs/op)
  utf8 decode         1002 MB/s    (261573 ns/op, 0 allocs/op)
  int loop             693 M/s     (2883927 ns/op, 0 allocs/op)
  csv sort 1M×8         18 M/s     (54789071 ns/op, 2 allocs/op)
```

(Your numbers will differ — that's the point. These are from one machine.)

## What it measures

Pure-NURL throughput for the primitives the rest of the ecosystem is built on:

| benchmark | what it does | unit |
|-----------|--------------|------|
| `sha256` | hash a 1 MiB buffer | MB/s |
| `json parse` | parse a generated JSON document | MB/s |
| `sort i64` | sort 50 000 integers | M elements/s |
| `cbor decode` | decode a CBOR array | MB/s |
| `utf8 decode` | walk a multi-byte UTF-8 string | MB/s |
| `int loop` | a tight data-dependent integer loop | M iters/s |
| `csv sort 1M×8` | sort 1 000 000 8-column CSV rows by (type, date, uuid) | M rows/s |

The `csv sort` benchmark parses a generated 1 M-row, 8-column CSV with the
standard library's arena CSV reader (`csv_table_from_string`) at setup, packs
each row's `(type, date, uuid)` keys into one non-negative i64, then times an
in-place integer sort of those keys. On the machine above it sorts a million
rows in ~55 ms — matching a hand-tuned pre-1.0 reference that a comparison-based
`sort_by` closure was several times slower than. Two things made the difference,
both worth knowing:

- **Read cells off the view pointer, never with `nurl_str_get`.** A CSV cell
  view is a bare pointer into one big arena buffer with no interior NUL, and
  `nurl_str_get` bounds-checks with `strlen` — so a single read scans to the end
  of the file. Doing that per byte turned a sub-second extract into *minutes*
  (O(N²)). Byte access is `# i . p k` on the `*u` view.
- **Sort integers, not through a comparator closure.** Parse each row's keys
  *once* into a packed integer (the "parse keys once" lesson), and sort with an
  inline quicksort/insertion-sort — a closure call per comparison, ~20 M of
  them, is the whole gap between fast and slow.

Each row also reports **allocations per op** — the NURL-level heap allocations
the operation costs — alongside wall time, because how much a routine allocates
is as much a part of its cost as how long it runs. (That `sha256` shows ~16 000
allocs/op is a genuine finding about the stdlib hasher, surfaced by measuring
rather than assuming.)

## How it's honest

- Built on the standard library's `std/bench` harness: each benchmark **auto-
  scales its iteration count** until a timed pass clears ~50 ms, so ns/op is
  stable even for sub-microsecond work, and wall time comes from a **monotonic
  clock** (immune to NTP slew).
- Inputs are generated **deterministically at setup**, and setup is **not
  timed** — `std/bench` snapshots the clock and the allocation counter around
  the timed loop only.
- The `int loop` uses a data-dependent xorshift mix, not a plain sum, so the
  optimiser can't collapse it to a closed form and measure nothing.

## Zero setup, runs anywhere

No GPU, no model download, no network, no configuration. `bench` has **no
dependencies beyond the standard library** and runs anywhere NURL runs.

## Usage

```
bench                 run the whole suite
bench <name…>         run only the named benchmarks   (bench sha256 "utf8 decode")
bench --list          list the benchmark names
bench --json          emit the measurements as JSON — a CI baseline or a
                      regression gate
```

`--json` gives one object per benchmark (`name`, `ns_per_op`, `allocs_per_op`,
`throughput`, `unit`), so a CI job can diff today's numbers against a committed
baseline and fail on a regression.

## Scope

`bench` proves the *stdlib* throughput story — the layer every package shares.
Package-specific claims (a model's tokens/s, a gradient's parity, an HTTP
server's conformance) live as `benches/*.nu` in their own packages, run with
`nurlpkg bench`, where they have the model, GPU or fixture they need.
