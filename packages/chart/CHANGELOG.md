# Changelog

## [0.1.5] — 2026-10-10

Requires NURL 0.72.0 (`slice_of_str`). Loops that walked a string with
`nurl_str_get` — which measures the string from its start on every call,
so a scan is quadratic in the string's length, and nurlc 0.72 warns
about the shape — read through a view measured once (`slice_of_str` +
`slice_byte`). No change in behaviour.

## [0.1.4] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.1.3 does
not compile under 0.71.0.

## [0.1.3] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more: every `string_free`, `vec_free`,
`vec_free_with` and `args_free` call (21) is gone — the compiler drops the
token vectors, label vectors, rendered strings and the argument parser at
the end of their scopes. The docs no longer tell callers to free a
rendered `String`; its owner drops it. Same output for every mode, flag and
error path, leak-free under LSan, and the same instruction count
(+0.00 % spark / hist / line, −0.34 % bar).

## 0.1.2

Formatting only: `nurlfmt` normalised trailing comment alignment in the
sources when the toolchain's ownership hardening went through (#1107), and
this package was never republished afterwards, so the registry has been
serving 0.1.1 with different bytes ever since. No behaviour changes.
