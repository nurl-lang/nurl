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
hub dir   org/repo --jobs 4 --conns 8  # 4 files at once, 8 connections each
```

A **ref** is a Hugging Face shorthand or a URL:

| ref | means |
|-----|-------|
| `org/repo` | the whole repository at `main` |
| `org/repo/path/to/file.gguf` | one file |
| `org/repo@revision[/path]` | pinned to a branch, tag or commit |
| `hf.co/org/repo/…` | the `hf.co/` shorthand (prefix stripped) |
| `https://huggingface.co/org/repo` | the repository page a browser shows: the whole repo (`/tree/<rev>`: at that revision) |
| `https://huggingface.co/org/repo/blob/<rev>/path` | a file page (`/resolve/` and `/raw/` too): that one file at `<rev>` |
| `https://…` | any other URL: downloaded as-is |

A Hugging Face web URL is read as the ref it shows, never downloaded as a
web page; that holds for `hf.co`, `www.huggingface.co`, the `$HF_ENDPOINT`
mirror's host and the same URL without `https://`. A URL hub cannot fetch
(a dataset, a Space, a subdirectory of a tree) is an error.

## From NURL

The one call a consumer wants is `hub_get` — hand it whatever the user typed
and get back a usable local path:

```nurl params="s user_arg"
$ `deps/hub/src/hub.nu`

// a local path passes straight through; an HF ref is fetched (a bare
// org/repo → a directory, a ref with a file → that file's path)
: !String String m ( hub_get user_arg )
?? m {
    T path → {}   // open ( string_data path ) — a dir for embed/whisper, a file for gguf
    F e → {}      // …
}
```

So `embed serve BAAI/bge-m3`, `embed serve ./my-model`, and
`nurllama run org/repo/model.gguf` all resolve through one call. When you need
to force the shape, `hub_dir` returns a repo directory and `hub_file` returns a
single file's path. All three are idempotent — a second call with everything
cached touches no network.

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
- **Parallel, resumable, constant-memory downloads** (next section). A multi-GB
  model costs no RAM to fetch, and an interrupted pull picks up where it
  stopped.
- **Integrity on demand.** `hub verify` re-hashes every cached blob against its
  recorded sha256 and refuses drift — a flipped byte in the cache is an error.

## Fast downloads

Hugging Face's CDN holds one HTTP connection to a fraction of a megabyte a
second, and the rate grows about linearly with connections. So hub never
fetches a large file over one:

- **A file in ranges.** A file of known size above one chunk (32 MiB) is cut
  into chunks, and up to `--conns` connections (default 8) each take the next
  chunk not yet on disk, ask for it with `Range: bytes=a-b` and write what
  arrives straight into the staging file at its offset. Memory stays constant
  whatever the size.
- **Files side by side.** `hub dir` / `hub pull` fetch `--jobs` files at once
  (default 2), each with its own connections — 16 in all by default. Small
  files (one chunk or less) take one connection each.
- **One progress line** (on a terminal) with the bytes and the total rate of
  every transfer of the pull.

Defaults come from `$HUB_JOBS`, `$HUB_CONNS` and `$HUB_CHUNK` (bytes); from
NURL, `hub_dir_opts` / `hub_file_opts` / `hub_get_opts` take a `HubOpts`
(`hub_opts_default` reads the environment).

**Resume, at range granularity.** A chunk that has landed is flushed to the
device and only then recorded in a sidecar next to the staging file:

```
blobs/sha256-<hex>.part          the file being assembled, at full length
blobs/sha256-<hex>.part.ranges   hub-ranges 1 <size> <chunk>, then one finished chunk a line
```

An interrupted pull — killed, crashed, the network gone — resumes with exactly
the chunks the record does not list; a recorded chunk is never fetched again
(a record kept in another `$HUB_CHUNK` still counts). Within one run a dropped
or stalled connection (60 s without a byte) is retried from the first byte not
yet written, with back-off. Two hub processes never write one file: the
staging file is locked while a transfer runs (the kernel drops the lock when a
process dies), and the second is refused. A staging file is named by the
sha256 the file will have (or, without one, by its name and a digest of its
URL), so two files of a repository never share one. A partial download hub
0.2 left (`blobs/<name>.part`) is taken over as the prefix it is, when the
file has a published sha256 to check it against.

**Integrity.** The ranges are written out of order, so when the last one lands
the whole file is hashed in order, and the bytes must hash to the sha256
Hugging Face publishes: a corrupted or substituted range is an INTEGRITY
FAILURE, the staging file and its record are discarded, and the next pull
starts clean.

A file of unknown size (a plain URL) or one chunk or smaller streams over one
connection with an incremental sha256 and resumes with `Range: bytes=<n>-`.

## Dependencies

None beyond the standard library (the streaming HTTP client, sha256, fs). No
Python, no `huggingface_hub`, no `git-lfs`.

## Tests

- `tests/hub_test.nu` — offline gates: ref parsing, name safety, URL resolution,
  manifest round-trip, the blob GC-sharing rule, the chunk layout, staging
  names, the range record (round trip, a torn line, another chunk size, another
  file size) and the tuning variables.
- `tests/hub_test.sh` — online, against a tiny real repo: the symlink farm, the
  **HF-oracle** (every LFS blob's address equals the API's `lfs.oid`), corruption
  detection, single-file dedup, GC, a resumed download; then in 64 KiB ranges:
  a parallel repo fetch under the oracle, a resume from a partial range record,
  a corrupted recorded range caught by the sha256 check, a hub 0.2 partial
  taken over, and a real `kill -9` mid-transfer (with a second hub refused
  meanwhile) resumed without refetching the recorded ranges. Skips cleanly when
  offline.
