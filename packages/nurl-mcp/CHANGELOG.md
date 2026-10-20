# Changelog

All notable changes to this package are documented here.

## [0.14.0] — 2026-10-20

Requires NURL 0.76.0 (`nurl --stdin NAME`).

### Changed

- **Diagnostics name the caller's file.** Inline `source` is handed to
  the toolchain on stdin under `filename` (new, default `main.nu`):
  `nurlc --stdin` for `nurl_check`, `nurl --stdin` for `nurl_build` /
  `nurl_run`, `wb_build_text` for `nurl_build_wasm`. Errors read
  `main.nu:6:12: …` instead of `/tmp/nurl-mcp-<pid>-<n>.nu:6:12: …` — a
  path the agent never wrote and cannot use — and no temp `.nu` is
  written and deleted per call.
- **`nurl_check` is the front end only** (`nurlc --check`): the same
  type and borrow checks, without generating and discarding the IR.
- **`nurl_api package=`** opens with the package's module index (each
  module's surface size and opening sentence); `module=` (one, or
  `'txn,db'`) renders surfaces whole. A package larger than one reply
  answers with the index instead of being cut mid-module; an impl renders
  its method signatures, not their bodies. An unknown module is a tool
  error listing the package's modules.
- **`nurl_docs` serves `formal/`** — the mechanized memory-safety proof:
  `formal/CLAIM.md`, `formal/RULES.md`, and the probe table
  `formal/corpus/map.tsv`, whose rows `name=… query=…` returns; `name=`
  with `query=` searches one document. Shared with the playground server
  (`msearch_docs_tool`).
- **Registry answers are cached for ten minutes**: a repeated
  `nurl_api` query no longer waits on the registry for its package
  footer (1.4 s → 50 ms measured), `nurl_grep` packages likewise, and
  `module=` after a package index is free.

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
