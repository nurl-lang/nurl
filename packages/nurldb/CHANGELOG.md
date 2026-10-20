# Changelog

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
