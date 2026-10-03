# Changelog

## [0.4.0] — 2026-10-03

Nothing is released by hand any more.

- `Gguf`, `GgufW` and `GgufS` are handles instead of `*Gguf` / `*GgufW` /
  `*GgufS` pointers: every copy is the same file or writer, and the last
  owner releases it — a `Gguf` unmaps its file, a streaming writer closes
  its file if `gws_finish` did not, as `gguf_close` / `gws_free` did.
  `gguf_open` / `gguf_parse_bytes` → `!Gguf String`, `gw_new` →
  `!GgufW String`, `gws_create` → `!GgufS String`. `gguf_close`, `gw_free`
  and `gws_free` are optional early releases.
- `gguf_parse_bytes` takes its buffer: the `Gguf` keeps the bytes its
  tensors point into (the no-mmap fallback of `gguf_open` hands it the
  file's bytes the same way).
- New: `gguf_kvs` / `gguf_tensors` (the tables, borrowed — for code that
  read `. g kvs` / `. g tensors`), `gguf_none` / `gguf_is_open` (an empty
  slot).
- Every `string_free` / `vec_free` / `json_free` / `args_free` in the
  library and the CLI is gone, as are the hand-written teardown helpers.

## 0.3.4

`--version` reported 0.3.2 while the manifest said 0.3.3.

The string is a literal in the source and nothing derives it from `nurl.toml`,
so the bump to 0.3.3 moved one and not the other. A published version cannot be
replaced, only superseded — which is what this is.

## 0.3.3

`gw_free`, `gws_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.3.2 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
