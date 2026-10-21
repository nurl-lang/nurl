# hub changelog

## [0.2.4] — 2026-10-21

### Fixed

- Installable as a dependency: the sources in `src/` imported their siblings as
  `src/<name>.nu`, which resolves only with the package root as the working
  directory, not under a consumer's `deps/hub/`. They are written relative to
  the importing file (`<name>.nu`) now, which resolves in both layouts.

## [0.2.3] — 2026-10-14

Requires NURL 0.73.0.

### Changed

- The staging file of a download is a `?File` until it is open, instead of a `File` made up from a null address. No function is `unsafe` any more.
- 1 fewer functions are `unsafe` than in 0.2.2 (0 left).

## [0.2.2] — 2026-10-12

Requires NURL 0.73.0, in which a standard-library handle holds its
state in a `( Shared T )` (stdlib/core/rcbox.nu): a zero handle is the
cast `# File # s 0`, no longer the literal `@ File { # s 0 }`. The
published 0.2.1 does not compile under it.

### Changed

- The zero `File` handle this package keeps until one
  is made is built with the cast. No change in behaviour.
- `hub --version` prints the version from `nurl.toml`
  (`( pkg_version )`). It printed the hand-written `0.2.1`.

## [0.2.1] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.2.0 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.2.0] — 2026-10-03

Nothing is released by hand any more.

### Removed

- `hub_ref_free` and `hub_file_free`: `HubRef` and `HubFile` are plain values
  whose Strings the compiler drops with their binding — delete the calls
  (nothing outside the package called them).

### Changed

- Every `string_free` / `vec_free_with` / `json_free` / `args_free` in the
  library, the CLI and the tests is removed (234 calls). Same output from
  every CLI command; instructions:u for `verify` / `ls` / `dir` on a cached
  repository within ±0.01 %.

Requires NURL 0.69.0.

## 0.1.4

`hub --version` says 0.1.4 — the literal in main.nu had not moved with the
manifest, so the 0.1.3 binary reports 0.1.2 (the repo's version-string
gate caught it in CI, after the publish). Otherwise identical to 0.1.3.

## 0.1.3

`hub_ref_free` and `hub_file_free` take **`sink`** parameters: a free
function must consume the handle it releases, so the compiler-ownership
hardening in the toolchain (#1107) can prove the caller cannot use it
again. The change landed in the monorepo with that PR but this package was
never republished, so the registry kept serving 0.1.2 — the same source
minus this one keyword. No behaviour change; republished so dependents
built against the monorepo (whisper 1.2.0, embed 0.4.0) pass the publish
gate's byte-identity check.

## 0.1.1

- Add `hub_get` — the one call a consumer wants: an existing local file or
  directory passes straight through, otherwise the argument is a Hugging Face
  ref and is fetched (a bare `org/repo` through `hub_dir`, a URL or a ref with a
  file subpath through `hub_file`). This is the seam embed/whisper/nurllama
  resolve their model argument through, so a local path and an HF ref both work.
- Make the package consumable: source files no longer `$`-import their siblings
  via `src/…` (which resolved against a consumer's build root, not hub's). A
  consumer now imports every hub file — `$ deps/hub/src/{store,hf,pull,hub}.nu` —
  matching the convention gguf/tokenizer/safetensor use. No API change.

## 0.1.0

- Initial release. Fetch models from Hugging Face into one shared, verified,
  content-addressed cache (`$NURL_MODELS` or `~/.nurl/models`), shaped like
  Hugging Face's own hub cache. `hub_file` (one file → path), `hub_dir` (a whole
  repo → a real model directory via a snapshot symlink farm), `hub_ls` /
  `hub_path` / `hub_verify` / `hub_rm`, and a `hub` CLI. Resumable
  constant-memory downloads with sha256 provenance against HF's published
  `lfs.oid`. Zero dependencies beyond the standard library.
