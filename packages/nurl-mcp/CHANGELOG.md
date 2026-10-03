# Changelog

All notable changes to this package are documented here.

## [0.13.1] — 2026-10-03

No change to the MCP tools, their arguments or their results. Requires
NURL 0.69.0.

### Changed

- Nothing is released by hand any more: every `string_free` / `vec_free` /
  `json_free` / `output_free` / `args_free` and the final `mcp_server_free`
  are gone. The build-workspace writer reports failure as its `b` result
  instead of through an 8-byte heap flag allocated and freed per build.
