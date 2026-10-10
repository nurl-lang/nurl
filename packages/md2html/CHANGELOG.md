# Changelog

## [0.1.4] — 2026-10-10

Requires NURL 0.72.0 (`slice_of_str`). Rendering is linear in the
document. Finding each line's end read the document with `nurl_str_get`,
which measures it from its start on every call, so a large document
rendered in quadratic time: the 1.2 MB NURL changelog took 36.5 s and
now takes 0.02 s, a 263 KB table-heavy document 1.11 s and now 0.00 s.
The document is measured once (`slice_of_str`) and every scan reads the
view (`slice_byte`); the line helpers take it from their caller. Output
is byte-identical.

## [0.1.3] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more: the converter and the CLI no longer
call `string_free`, `vec_free`, `vec_free_with` or `args_free` — the input
string, the heading-id scratch string, the list-state vector and the argument
parser are dropped at the end of their scopes. The library API
(`md_to_html`) is unchanged.

