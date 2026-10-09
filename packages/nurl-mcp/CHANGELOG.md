# Changelog

All notable changes to this package are documented here.

## [0.13.2] — 2026-10-09

Requires NURL 0.72.0, which tracks a view wherever it goes and rejects
one that outlives what it views. The published 0.13.1 does not compile
under 0.72.0.

### Changed

- The `--token` value reaches the HTTP transport as an argument of
  `run_http` (`run_http srv host port token`) instead of through a
  global view of `main`'s String, which 0.72.0 rejects: a global
  outlives the String it points into. Requests are authenticated as
  before.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.13.1] — 2026-10-03

No change to the MCP tools, their arguments or their results. Requires
NURL 0.69.0.

### Changed

- Nothing is released by hand any more: every `string_free` / `vec_free` /
  `json_free` / `output_free` / `args_free` and the final `mcp_server_free`
  are gone. The build-workspace writer reports failure as its `b` result
  instead of through an 8-byte heap flag allocated and freed per build.
