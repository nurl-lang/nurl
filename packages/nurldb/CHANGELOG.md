# Changelog

## [0.3.1] — 2026-11-11

### Fixed

- `nurl.toml`, `CHANGELOG.md` and `README.md` have LF line ends in the
  tarball. 0.3.0 was packed from a checkout that held them with CRLF, so
  the registry's files differed from the repository's. No code changed.

## [0.3.0] — 2026-11-05

Requires NURL 0.88.0 (std/pfile.nu's `pfile_try_lock`).

### Added

- **A TEXT value may be longer than a page.** A row whose tuple would be
  larger than 2 KiB keeps its longest TEXT values out of line, longest
  first, each on a chain of overflow pages (`ovf.nu`), and the row holds
  the value's length and first page. A value can be up to 2^31 - 1 bytes
  long; until now an INSERT of a row larger than a page failed with "a row
  larger than a page". The pages are written before the tuple that names
  them and never change after, each logged whole, so redo rebuilds them
  and a crash or a rollback leaves only unread pages, like a dead row
  version. `tests/ovf_test.nu` covers every size edge, a scan, LIKE, an
  UPDATE of either column, a rollback, four threads at once, a clean close
  and a crash.
- **The database directory is locked while it is open.** `db_open` takes an
  exclusive lock on the file `lock` in the directory (`pfile_try_lock`:
  flock(2), LockFileEx on Windows) and refuses a second open, by another
  process or by this one: "the database is already open". Before, a second
  open recovered from a log the first was still appending to, and both
  wrote the same files. The lock goes with `db_close`, `db_crash` or the
  process, so a killed server leaves no stale lock.

### Changed

- The data file's format is version 2, which nurldb 0.1 and 0.2 cannot
  read when a value is kept out of line. A version 1 database opens and
  becomes version 2 at the checkpoint every open makes. A database
  written by a newer version than this one is refused instead of misread.
- The SQL lexer's token type is `SqlTok`, not `Tok`. NURL has no
  namespaces, and a program that imported both nurldb and the tokenizer
  package (nurllama) had two types named `Tok`.

## [0.2.0] — 2026-11-03

Published with NURL v0.86.0. Requires std/net's `NetDialer` and
std/net_sim.nu's `netsim_crash`.

### Added

- `serve_on db listener` — serve a listener the caller made: `tcp_listen`'s, or a node's of a simulated network (`netsim_listen`). It returns once the listener stops accepting (closed, or its node crashed) and the connections it accepted have ended; `serve` is `serve_on` over `tcp_listen`.
- `client_connect_with dialer host port` — the client dialed through a std/net `NetDialer`: the kernel's, or a simulated network's node (`netsim_dialer`).
- `client_set_timeout client ms` — each read and write of a statement waits at most `ms`, so a server that crashed with the statement in hand fails the statement instead of holding its client forever (found by the DST flagship scenario, NURL agora #262).
- `db_crash db` — the database dropped as a killed process leaves it: the log's flusher stopped, no checkpoint, dirty pages lost. `db_open` on the directory then recovers from the log, so a test can crash and restart a server inside one process.

### Changed

- The checkpointer takes no last checkpoint when its server stops. What is committed is in the log, and recovery replays it.

## [0.1.1] — 2026-10-26

### Fixed

- `wal_append` reads the log buffer's start before it grows the buffer.
  The compiler now tracks a binding read out of a field as a borrow of
  that field (NURL agora #111). Growing `buf` therefore ends the other
  borrows of the guard's value, and `b` was read after that. The
  behaviour is unchanged.

## [0.1.0] — 2026-10-20

Requires NURL 0.75.0 (`std/atomic.nu`, `std/rwlock.nu`, `std/pfile.nu`,
`locked_await`).

### Added

- A relational database in safe NURL, multi-threaded throughout, with no
  `unsafe` function: 8 KiB checksummed pages; a buffer pool of
  reader-writer-latched frames with atomic pins and clock eviction that
  keeps the WAL rule; a write-ahead log with group commit; snapshot
  isolation (MVCC) with a lock manager, FIFO waits, deadlock detection and
  serialization failures; B+tree indexes with latch crabbing; crash
  recovery (torn tail cut, redo from the checkpoint, unfinished
  transactions aborted) with full-page images; a catalog stored in tables
  of its own; SQL — CREATE TABLE / INDEX, INSERT, SELECT with WHERE, one
  JOIN, GROUP BY / HAVING, ORDER BY, LIMIT, DISTINCT, UPDATE, DELETE,
  transactions, EXPLAIN — with aggregation over a table scan run on four
  threads; a TCP server with a thread per connection and a checkpointer
  thread; a CLI (`shell`, `-c`, `serve`, `client`, `bench`).
- 151 tests in nine files, among them eight sessions moving money while
  two total it, and a child killed with SIGKILL mid-flight whose every
  acknowledged commit survives recovery.
