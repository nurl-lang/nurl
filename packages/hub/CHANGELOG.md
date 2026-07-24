# hub changelog

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
