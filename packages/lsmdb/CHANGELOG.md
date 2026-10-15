# Changelog

## [0.3.0] — 2026-10-14

### Changed

- No `unsafe` function left (104 in the previous release). The store
  is a `Locked`: two threads using one database took turns only by
  luck before — every call reached the state through `arc_ptr`. The
  memtable and the write-ahead log are values the store owns and
  changes through `inout`; a table reader keeps its block cache and
  file behind its own lock and its Bloom filter in an `Arc` beside it,
  so a get the filter rules out takes no lock at all; cursors are `Rc`
  handles that never leave the operation that opened them.
- Keys are compared through byte views (`slice_bytes_cmp`, memcmp)
  instead of raw pointers, and the merge iterator keeps a copy of every
  source's head, so a step reads the heads without opening a cursor and
  each entry costs one cursor call to move and one to read its value.
- Measured against the previous release (300 000 keys, five interleaved
  runs, medians): batched writes and absent reads equal, point reads
  +7 %, a full scan 229 ms against 241, compaction equal.
- `stats` counts filter-answered gets for the store's life (the tables
  of a compaction no longer take their counts with them).

## [0.2.5] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- 2 fewer functions are `unsafe` than in 0.2.4 (104 left).

## [0.2.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.2.3 does not compile under it.

### Changed

- The zero `File` handles the WAL and the tables keep until one is
  opened are built with the cast `# File # s 0`: a standard-library handle
  now holds its state in a `( Shared T )`.
- The file a table or log replaces is dropped by the store; the
  `mem_take` before each such store is gone.

## [0.2.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.2.2 does not compile under it.

### Changed

- `Lsm`, `LsmIter`, `MemTable`, `SstCursor`, `SstReader`, `SstWriter` and
  `Wal` keep their state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- 7 fewer functions are `unsafe` than in 0.2.2.
- The `lsmdb` command binds the opened database straight from `lsm_open`'s
  result, and a flush or a compaction its table writer straight from
  `sst_create`, instead of building a null handle first.

## [0.2.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.2.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

## [0.2.0] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more.

- `Lsm`, `MemTable`, `Wal`, `SstWriter`, `SstReader` and `SstCursor` are
  handles instead of `*T` pointers: every copy is the same object and the
  last owner releases it. A store, writer or reader closes its file when its
  last owner lets go; a cursor holds a share of its table. `lsm_open`,
  `sst_open`, `sst_create` and `wal_open` return the handle (`!Lsm String`,
  …); every function that took `* Lsm` / `* MemTable` / … takes the handle.
- `lsm_close`, `mt_free`, `sc_free`, `sst_close`, `wal_close`,
  `lsm_get_free`, `lsm_scan_free` and `sst_hit_free` are optional early
  releases.
- New `wal_reopen w path`: a flush reopens its log in place.
- The merge iterator opens each cursor once per step: scan and compaction
  run 6–7 % fewer instructions, loads 2.5 % fewer.

## 0.1.1

`lsm_get_free`, `lsm_scan_free`, `mt_free`, `sc_free`, `sst_hit_free` and 3 more now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

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
