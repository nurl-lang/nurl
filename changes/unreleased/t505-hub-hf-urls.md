### Fixed

- **hub reads a Hugging Face web URL as the ref it names** (Agora #505,
  packages/hub 0.2.5). `hub pull https://huggingface.co/org/repo` — the
  address a browser shows — pulls the repository, `…/tree/<rev>` the
  repository at that revision, and `…/blob/<rev>/<path>` (or `/resolve/`,
  `/raw/`) that one file. Every `https://` ref used to be downloaded
  as-is, so the repository page's HTML landed in the cache instead of the
  model. `hf.co`, `www.huggingface.co`, the `$HF_ENDPOINT` host and the
  URL without `https://` work the same; a dataset, a Space or a tree
  subdirectory is an error rather than a page download.
