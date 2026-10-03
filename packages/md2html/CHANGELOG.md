# Changelog

## [0.1.3] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more: the converter and the CLI no longer
call `string_free`, `vec_free`, `vec_free_with` or `args_free` — the input
string, the heading-id scratch string, the list-state vector and the argument
parser are dropped at the end of their scopes. The library API
(`md_to_html`) is unchanged.

