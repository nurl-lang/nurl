# hub changelog

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
