# nurldb

A relational database in pure NURL, multi-threaded throughout: SQL over
B+tree-indexed tables, snapshot-isolation transactions, a write-ahead log
with group commit, crash recovery, and a TCP server — 6 000 lines with
no `unsafe` function in them.

```sh
nurldb ./data -c "CREATE TABLE emp (id INT PRIMARY KEY, name TEXT NOT NULL, salary REAL);
                  INSERT INTO emp VALUES (1, 'Ada', 120.0), (2, 'Bob', 95.5);
                  SELECT name FROM emp WHERE salary > 100"
nurldb ./data                 # a shell: statements end with ';'  (\dt, \q)
nurldb serve ./data 5433      # over TCP, one thread per connection
nurldb client 127.0.0.1 5433
nurldb bench ./bench 8 5      # transfers from 8 sessions for 5 s
```

As a library:

```
$ `deps/nurldb/src/nurldb.nu`

: Db d ?? ( db_open `./data` ( db_default_opts ) ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
: ~ Session s ( session_new d )
?? ( session_exec s ( string_from `SELECT name FROM emp WHERE id = 1` ) ) {
    T r → ( nurl_print ( string_data ( result_text r ) ) )
    F e → ( nurl_println ( string_data e ) )
}
( session_close s )
( db_close d )
```

A `Db` is shared by every thread that uses it; each thread works through
a `Session` of its own.

The server and its client take the network from the caller as well:
`serve_on db listener` serves any `TcpListener` (`tcp_listen`'s, or a
node's of a simulated network, std/net_sim.nu) and returns once it stops
accepting and its connections have ended; `client_connect_with dialer
host port` dials through a std/net `NetDialer`; `client_set_timeout` bounds
how long a statement may wait for its answer. `db_crash` drops a database
as a killed process leaves it, so a test can crash a server and reopen
its directory inside one process — the DST flagship scenario
(`compiler/tests/dst_flagship.nu`, NURL's docs/SIMULATION.md) runs nurldb
under a partition and a crash-restart that way.

## SQL

```
CREATE TABLE t ( col type [NOT NULL] [PRIMARY KEY], … [, PRIMARY KEY ( col, … )] )
    type: INT | INTEGER | BIGINT | REAL | FLOAT | DOUBLE | TEXT | VARCHAR [(n)] | BOOL | BOOLEAN
CREATE [UNIQUE] INDEX name ON t ( col, … )
INSERT INTO t [( col, … )] VALUES ( expr, … ) [, ( … ) …]
SELECT [DISTINCT] expr [[AS] name], … | *
    [FROM t [[AS] a] [[INNER] JOIN u [[AS] b] ON expr]]
    [WHERE expr] [GROUP BY expr, …] [HAVING expr]
    [ORDER BY expr [ASC | DESC], …] [LIMIT n [OFFSET n]]
UPDATE t SET col = expr, … [WHERE expr]
DELETE FROM t [WHERE expr]
BEGIN | COMMIT | ROLLBACK | CHECKPOINT | EXPLAIN select
```

Expressions: literals, columns (`col`, `t.col`), `+ - * / % ||`,
comparisons, `AND OR NOT`, `IS [NOT] NULL`, `[NOT] LIKE`, `[NOT] BETWEEN`,
`[NOT] IN (…)`, `COUNT(*) COUNT SUM AVG MIN MAX`. NULL follows SQL:
arithmetic and comparisons with NULL are NULL, `AND`/`OR` are
three-valued, `WHERE` keeps a row only when its condition is TRUE. `ORDER
BY` takes a select-list alias or position.

## How it is built

| Layer | File | What it does |
|---|---|---|
| pages | `page.nu` | 8 KiB pages: LSN, number, type, CRC-32, chain links |
| buffer pool | `bufpool.nu` | frames under reader-writer latches; pins, dirty and clock bits are atomics; a page table under its own latch; clock eviction that never waits on a latched frame; a dirty victim is written after the log up to its LSN (the WAL rule), its checksum computed on a copy |
| log | `wal.nu` | records `[len][crc][payload]`, LSN = log position; appenders copy into a shared buffer, one flusher thread writes and `fdatasync`s it and wakes every committer it covered: **group commit** |
| heap | `heap.nu` | slotted pages of tuple versions (xmin, xmax, cmin, cmax); every change logged first, the same code redoing it |
| transactions | `txn.nu` | ids, the commit log, snapshots, visibility; a lock manager with shared/exclusive locks, FIFO waiting and a waits-for graph checked at every wait (**deadlock detection**) |
| tables | `table.nu` | MVCC insert/update/delete/scan; a writer meeting a version another running transaction claimed waits for it, one claimed by a transaction that committed after its snapshot gets a **serialization failure** |
| keys, B+tree | `keys.nu`, `btree.nu` | memcmp-ordered keys; **latch crabbing** — readers hand over hand under read latches, inserts optimistic under the leaf's write latch, pessimistic top-down with ancestors let go above every node with room; root splits through an anchor page |
| database | `db.nu` | the catalog as tables of its own; unique keys under key locks; open with **recovery** (torn tail cut, redo from the checkpoint, unfinished transactions aborted); sharp checkpoints; **full-page images** after each checkpoint |
| SQL | `sql.nu`, `exec.nu` | a parser into an expression arena; Volcano operators (`% Op`, `next inout self`): seq/index scans, filter, hash and nested-loop joins, hash aggregation, sort, distinct, limit; an aggregate over a table scan runs on **four threads**, each over a share of the pages |
| server | `server.nu`, `main.nu` | TCP, a thread per connection, a line protocol; the CLI |

Rollback needs no undo: a transaction's versions are invisible once the
commit log says it aborted. A failed statement panics — a serialization
failure, a deadlock, a duplicate key, a type error — and `recover` around
it aborts the transaction; the page latches, locks and memory the
statement held are released by the unwind (NURL's panic journal).

## Tests

```sh
cd packages/nurldb
for t in tests/*_test.nu; do
    NURL_STDLIB=../.. ../../nurl.sh $t /tmp/t && /tmp/t || echo "FAILED: $t"
done
```

| Test | What it shows |
|---|---|
| `wal_test` | records round-trip; 8 threads append and commit; 400 commits share ~100 writes; a torn tail is cut |
| `bufpool_test` | 200 pages through 32 frames; 6 writers and 2 readers on random pages, no torn page seen; a damaged page refused |
| `txn_test` | visibility by snapshot; 300 rounds of two threads locking in opposite orders, one refused each time |
| `table_test` | 8 threads insert 16 000 rows; deletes and snapshots; a bank of 64 accounts under 6 writers and 2 readers: conflicts retried, every total right |
| `btree_test` | key order; 20 000 keys sorted; 8 writers and 2 readers splitting leaves, inner nodes and the root under each other |
| `db_test` | catalog, unique keys, a waiter for a key a running transaction holds, 10 racing threads, CREATE INDEX on a populated table, reopen |
| `sql_test` | the SQL above, statement by statement |
| `conc_test` | 8 SQL sessions moving money while 2 total it; a 200 000-row GROUP BY on 4 threads and on 1 |
| `crash_test` | a child with 4 threads is killed with SIGKILL mid-flight, twice; every acknowledged commit survives and the money adds up; a transaction running at the crash stays undone once new ones commit |

Every test runs clean under AddressSanitizer and LeakSanitizer
(`NURL_SAN=1`).

On a laptop (`nurldb bench`, `fdatasync` at every commit): 810 transfers
per second from one session, 3 600 from eight — eight sessions share a log
write about four commits at a time. A GROUP BY over 200 000 rows takes
64 ms with its pages dealt out to four threads, 480 ms through the
one-thread plan (scan, filter, hash aggregate).

## Limits

- No VACUUM yet: dead row versions and their index entries stay, and the
  file only grows. Pages are never reused.
- Snapshot isolation, not serializable (write skew is possible).
- No subqueries, outer joins, `DROP`, or `ALTER`; DDL runs outside a
  transaction. One join per query.
- The log is cut at open (after recovery), not while the database runs.
- A failed statement rolls its transaction back (there is no savepoint).

## What it changed in NURL

Building it found gaps in the language and its memory model, each fixed
where it lives (see the CHANGELOG and `tools/fuzz/holes/h288`–`h298`):
atomics, reader-writer locks with read guards that lend frozen views, a
file type for positional I/O, `locked_await`; closures that count into a
caller's binding; guards held in struct fields, dropped through a panic,
and released at the end of a block that computes a value; a temporary
handed to a callee that panics; a parameter's copy passed `inout` to a
function that replaces one of its fields; a closure replaced through an
`inout` parameter, or handed a captured binding to one; a foreach over a
field.
