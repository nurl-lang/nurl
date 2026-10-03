# Changelog

## [0.1.5] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more.

- The CSV table in the `csv sort 1M×8` setup is a `CSVTable` value, not a
  `*CSVTable`: `stdlib/ext/csv.nu` made it a self-releasing handle that its
  last owner drops. The setup that parses it and extracts the sort keys is
  its own function, so the million-row table is dropped when that returns —
  before the timed sort allocates — with no `csv_table_free`. The CBOR
  benchmark's source document is built the same way.
- Every `string_free`, `vec_free`, `vec_free_with`, `json_free`, `rng_free`
  and `bench_result_free` call (36) and the private `__bench_free_args`
  helper are gone. `BenchRow` is a plain value its owner drops;
  `bench_row_free` is an optional early release.
- Same rows, same allocations per operation, leak-free under LSan. With
  every benchmark body run a fixed number of times, the instruction counts
  are unchanged (±0.01 %) except the CSV setup (+0.24 %, untimed): three
  strings per generated row are dropped at the end of the loop body instead
  of released by hand, and the compiler guards that drop with a run-time
  ownership flag (reported upstream).

## 0.1.4

The benchmark body's closure environment is no longer freed by hand; NURL 0.67.0 owns and drops it (#1141).

## 0.1.3

`bench_row_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.2 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
