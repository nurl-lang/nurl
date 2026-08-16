# Changelog

## 0.1.0 — 2026-08-16

First release. An embedded LSM-tree key/value store in pure NURL.

- Write-ahead log with a CRC-32 per record, fsynced before a write is
  acknowledged. Replay stops at the first torn record, keeps everything
  before it, and **truncates the log back to that point** so later writes
  are never stranded behind bytes replay refuses to walk past.
- Skip-list memtable over a single byte arena — index-based nodes, so
  nothing is allocated per key and the arena may grow under a node.
- Immutable SSTables: ~4 KiB blocks with a CRC-32 each, a block index
  keyed by each block's *last* key (correct when a key's versions
  straddle a boundary), a Bloom filter, and a 48-byte footer. Opening a
  table reads only the index and the filter; a get reads one block.
- 32-slot block cache per open table: a hit skips both the read and the
  checksum, so a scan verifies once per block rather than once per key.
- Compaction merges every table into one, keeping the newest version of
  each key and dropping tombstones.
- Snapshot reads: `--at SEQ` / `lsm_get_at` see the database exactly as
  it was after write SEQ.
- CLI: `put`, `get`, `del`, `scan`, `load`, `flush`, `compact`, `stats`,
  `bench`. Values are raw bytes end to end.

Three gaps in the standard library were closed to make this possible,
rather than worked around in the package: `file_sync` / `dir_sync`
(there was no fsync at all — only `fflush`), `file_truncate`, and
`write_bytes` (NURL could read binary from stdin but not write it to
stdout; `nurl_print` stopped at the first NUL byte, silently). The same
work made `std/deflate`'s CRC-32 table-driven and added a reusable
`Crc32` context, which took this store's point reads from 47 500/s to
~600 000/s and speeds up every gzip, tar and PNG user in the ecosystem.
