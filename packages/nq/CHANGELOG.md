# Changelog

## [0.1.3] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more: every `string_free`, `vec_free_with`,
`json_free` and `args_free` call is gone — the compiler drops the strings,
key vectors, parsed documents and the argument parser at the end of their
scopes. Same output for every filter shape, leak-free under LSan, and
within +0.2 % of the instruction count on a 40 000-element document.

## 0.1.2

Formatting only: `nurlfmt` normalised trailing comment alignment in the
sources when the toolchain's ownership hardening went through (#1107), and
this package was never republished afterwards, so the registry has been
serving 0.1.1 with different bytes ever since. No behaviour changes.
