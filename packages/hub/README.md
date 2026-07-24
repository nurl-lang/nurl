# hub

Fetch models from Hugging Face into one shared, verified, on-disk cache — the
front door the model packages were missing.

Today `whisper`, `embed`, `nurllama`, `onnx`, `yoloe` and `gguf` each begin with
"get a model from somewhere yourself." `hub` is the somewhere:

```
hub pull  org/repo                     # a whole repo → a model directory
hub pull  org/repo/model.gguf          # one file → a local path
hub file  org/repo/model.gguf          # force single-file, print the path
hub dir   org/repo                     # force whole-repo, print the directory
hub ls                                 # what's cached
hub path  org/repo                     # print the cached path (no fetch)
hub verify org/repo                    # re-hash every blob against its sha256
hub rm    org/repo                     # forget it, GC unshared blobs
```

A **ref** is a Hugging Face shorthand or a URL:

| ref | means |
|-----|-------|
| `org/repo` | the whole repository at `main` |
| `org/repo/path/to/file.gguf` | one file |
| `org/repo@revision[/path]` | pinned to a branch, tag or commit |
| `hf.co/org/repo/…` | the `hf.co/` shorthand (prefix stripped) |
| `https://…` | a direct URL, downloaded as-is |

## From NURL

```nurl
$ `deps/hub/src/hub.nu`

// ensure a whole model repo is local; get a directory an existing loader opens
: !String String d ( hub_dir `Qwen/Qwen2.5-0.5B-Instruct` )
?? d { T dir → { /* pass ( string_data dir ) to embed / whisper / a checkpoint loader */ } F e → { /* … */ } }

// ensure a single file is local; get its path
: !String String f ( hub_file `bartowski/SmolLM-135M-Instruct-GGUF/SmolLM-135M-Instruct-Q4_K_M.gguf` )
?? f { T path → { /* open ( string_data path ) with gguf / nurllama */ } F e → { /* … */ } }
```

`hub_dir` returns a real directory of the repo's files; `hub_file` returns one
file's path. Both are idempotent — a second call with everything cached touches
no network.

## The cache

`$NURL_MODELS` (or `$HUB_HOME`, else `~/.nurl/models`), shaped exactly like
Hugging Face's own hub cache:

```
~/.nurl/models/
  blobs/sha256-<hex>                        every file, downloaded once, by content
  models/<org>--<repo>/snapshots/<rev>/     a symlink farm = a model directory
      config.json        -> ../../../blobs/sha256-…
      model.safetensors  -> …
  manifests/<handle>                        one small JSON per model
```

Because a file is named by its content, two revisions (or a repo and a
single-file handle) that share a file **share the bytes on disk**, and `rm`
drops a blob only once no handle still references it.

## What it guarantees

- **Provenance.** Every large weight file is an LFS file, and Hugging Face
  publishes its sha256 in the repo's tree metadata. `hub` verifies the bytes it
  downloaded against that published sha256 — you get *Hugging Face's actual
  file* or a clean error, never a silent substitution. (Small non-LFS files —
  `config.json`, `tokenizer.json` — carry only a git blob id, so they are
  content-addressed locally without an external anchor.)
- **Resumable, constant-memory downloads.** Chunks stream straight to disk while
  an incremental sha256 consumes the same bytes. An interrupted pull leaves a
  `.part`; the next attempt sends `Range: bytes=<n>-`, re-hashes what's there and
  appends. A multi-GB model costs no RAM to fetch.
- **Integrity on demand.** `hub verify` re-hashes every cached blob against its
  recorded sha256 and refuses drift — a flipped byte in the cache is an error.

## Dependencies

None beyond the standard library (the streaming HTTP client, sha256, fs). No
Python, no `huggingface_hub`, no `git-lfs`.

## Tests

- `tests/hub_test.nu` — offline gates: ref parsing, name safety, URL resolution,
  manifest round-trip, the blob GC-sharing rule.
- `tests/hub_test.sh` — online, against a tiny real repo: the symlink farm, the
  **HF-oracle** (every LFS blob's address equals the API's `lfs.oid`), corruption
  detection, single-file dedup, GC, and a resumed download. Skips cleanly when
  offline.
