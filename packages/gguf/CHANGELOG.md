# Changelog

## [0.6.0] — 2026-10-14

Requires the NURL with `stdlib/std/mmap.nu`, the little-endian slice words
and the borrow rule for views of plain numbers handed to a safe function.

### Changed

- No function is `unsafe` any more (73 were). A `Gguf` holds the file as
  a `MappedFile`, the parser's cursor reads a checked view of it, and
  `gguf_tensor_bytes` lends a tensor's bytes as a `Slice u` held to the
  `Gguf`; `gguf_tensor_ptr` is `raw`.
- The dequantiser reads each block through a window of the block's own
  size and writes it through a window of its output, so every index
  inside is provably in range: one check per block. It is 2–4× faster
  than the pointer loops it replaces (1M elements: Q4_K 7.2 → 1.7 ms,
  Q6_K 11.9 → 3.3 ms, Q8_0 8.8 → 2.2 ms, F16 11.0 → 5.1 ms), with the
  same bytes out.
- `GgufW` and `GgufS` are `Rc` handles (every call changes them in place,
  which their `Arc` let two threads do at once); each call checks the
  state out and back in.

## [0.5.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.4.2 does not compile under it.

### Changed

- `Gguf`, `GgufS` and `GgufW` keep their state in an `Arc`
  (stdlib/std/arc.nu) instead of an `rcbox`. The share and drop hooks are
  ordinary safe functions — the Arc does the counting — and so are the
  constructors that build one from a whole value; every copy is still the
  same state, and its last owner releases it.
- 3 fewer functions are `unsafe` than in 0.4.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.

### Removed

- `gguf_none` and `gguf_is_open`: a slot that may hold no file is a
  `?Gguf`. NURL 0.73.0 reads a null handle literal as raw memory, and an
  option says the same thing safely.

## [0.4.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.4.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [0.4.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.4.0 does
not compile under 0.71.0.

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
