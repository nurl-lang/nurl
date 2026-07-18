# Changelog

## 0.10.0

**Content-addressed datasets — data moved once, referenced by hash.**

Previously a dataset's slice rode inside every task payload, so N submits (or
the N rounds of an iterative algorithm) over the same data paid the transfer
N times. Now:

- **`src/blob.nu`** — a dataset is cut on a fixed grid into content-addressed
  **1 MiB blocks**, each keyed by its BLAKE3-256; the dataset is a manifest of
  those hashes. Workers cache blocks on disk (`$TMPDIR/swarmb_<hex>.blob`),
  verified against the hash on arrival — a corrupt or forged block is never
  written under a name it doesn't own.
- **Payload v4** (`wasm_gpu_chunk_payload_blobs`): a compute chunk references
  its blocks by hash instead of carrying the slice. The worker assembles
  `data[lo..hi)` from its cache (`gpu_chunk_assemble`); ANY missing or corrupt
  block fails the chunk **visibly** (`failed_chunks`), never silently.
- **Seeding** rides the ordinary job machinery: a `kind_blob` task with the
  SAME ring key as the compute chunk lands on the SAME worker (consistent
  hash), authenticated by the cluster HMAC token like every other payload.
  Blocks are seeded one at a time and confirmed before the compute chunks go
  out, so a block reaches its worker exactly once and re-submits ship only
  hashes.
- **`seeded_blocks`** in the task response reports how many blocks actually
  moved — `0` means the workers already held every block (a free re-run).
- Tests: `tests/blob_test.nu` (manifest determinism, cache store/append with
  corruption rejection, the HMAC seed handler, payload-v4 round-trip, slice
  assembly — 29 checks, ASan clean) and `tests/data_smoke.sh` (live: upload a
  12-block dataset, reduce it twice, assert the correct sum both times and
  `seeded_blocks` 12 then 0).

Depends on the `stdlib/net/relay.nu` `__read_exact` fix (a multi-megabyte
frame was dropped mid-read when a recv timeout was mistaken for a
disconnect) — see the toolchain CHANGELOG.

## 0.9.0 and earlier

See git history: unified node (relay/worker/mcp roles), token-HMAC auth,
distributed GPU compute over MCP (CUDA generator, sample/histogram, runtime
params), datasets over real data.
