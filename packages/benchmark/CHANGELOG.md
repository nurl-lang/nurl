# Changelog

## Unreleased

The CSV table in the `csv sort 1M×8` setup is a `CSVTable` value, not a `*CSVTable`: `stdlib/ext/csv.nu` made it a self-releasing handle that its last owner drops. `csv_table_free` stays only as an early release, so the million-row table is gone before the timed sort allocates.

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
