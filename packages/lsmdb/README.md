# lsmdb

An embedded key/value store in pure NURL — **a real LSM tree**, not a
file with a hash map in it: a write-ahead log, a skip-list memtable,
immutable CRC-checked SSTables with a Bloom filter and a block index,
ordered range scans, compaction, and snapshot reads.

```sh
nurlpkg install lsmdb

lsmdb put user:42 '{"name":"ada"}'   # fsynced before this returns
lsmdb get user:42
lsmdb scan --from user: --limit 20   # ordered, half-open range
lsmdb get user:42 --at 7             # the database as it was after write #7
lsmdb compact                        # merge tables, reclaim space
```

It is also a library — `src/lsmdb.nu` is the whole store behind ten
functions, and `src/memtable.nu`, `src/sst.nu` and `src/wal.nu` are
usable on their own if you need a sorted arena, a table format or a log.

## What it guarantees

**A write that returned is on the disk.** `lsm_put` appends to the log
and fsyncs it *before* the memtable is touched, so `kill -9`, a panic or
a power cut cannot lose an acknowledged write. (`--no-sync` trades that
away deliberately, for bulk imports.)

**A crash never leaves a state that reads wrong.** The flush and compact
sequences are ordered so that every point you can be killed at recovers:

| killed after… | on the next open |
| --- | --- |
| a log append | the write is there |
| a *partial* log append | the torn record is dropped, the log is truncated back to it, everything before it stays |
| writing a table, before the manifest | the table is an orphan file; its writes are still in the log |
| publishing the manifest, before the log reset | the log replays the same versions on top of the table — identical values at identical sequence numbers, so nothing doubles |
| compaction, before the manifest | the old tables are still named and still complete |

**Corruption is an error, never data.** Every block carries a CRC-32.
A block that fails it fails the read, loudly, naming the file — a store
you can rsync, snapshot or restore from a backup you do not fully trust
and still know that what comes back is what went in.

**Reads are versioned.** Every write gets a sequence number, versions of
a key sort newest-first, and `--at N` reads the database exactly as it
was after write N. Time travel is not a feature bolted on; it is the
ordering the tree already needed.

## The shape of it

```
        put/del                            get/scan
           │                                   │
           ▼                                   ▼
    ┌─────────────┐  fsync             ┌───────────────┐
    │  WAL (log)  │───────► disk       │   memtable    │  newest
    └─────────────┘                    ├───────────────┤
           │                           │  table 000003 │
           ▼                           ├───────────────┤
    ┌─────────────┐   flush            │  table 000002 │
    │  memtable   │──────────────►     ├───────────────┤
    │ (skip list) │                    │  table 000001 │  oldest
    └─────────────┘                    └───────────────┘
                                        first hit wins —
                                        including a tombstone
```

The **memtable** is a skip list over one byte arena: keys and values are
appended to a single growable buffer and a node is a row of integers
(offsets, lengths, sequence, kind) plus its forward links. Nothing is
allocated per node, so the arena can grow under a node without
invalidating it, and dropping a memtable is a handful of frees.

An **SSTable** is what a memtable becomes when it stops changing:

```
[data block 0][data block 1]…[index block][bloom block][footer 48B]

data block  entries sorted by (key ↑, sequence ↓), then [u32 crc32]
   entry    [u32 klen][u32 vlen][u64 seq][u8 kind][key][value]
index       one entry per block, holding that block's LAST key
bloom       [u32 nbits][u32 k][bits] — 10 bits/key, k=7
footer      index/bloom offsets + lengths, entry count, max sequence,
            and the magic "LSMDBv1\n"
```

Opening a table reads only the index and the filter; a get reads exactly
the one block it needs. **A table larger than RAM is an ordinary table.**

The index holds each block's *last* key rather than its first, which is
what makes the search correct when a key's versions straddle a block
boundary: "first block whose last key ≥ probe" always lands on the block
with the newest version, and the reader walks into the next block for the
rest of the run. Getting that backwards returns a *stale value* — no
crash, no checksum failure, just the wrong answer — which is the kind of
bug a test suite has to be built to catch on purpose.

**Compaction** merges every table into one, keeping the newest version of
each key and dropping tombstones. That is where space comes back, and it
deliberately throws history away: a snapshot older than a compaction can
no longer be served. LevelDB makes the same trade for the same reason.

## Speed

On one Linux x86-64 box, 50 000 keys of ~50 bytes (`lsmdb bench -n 50000`
— run it yourself, the numbers are the point, not the machine):

| | ops/s |
| --- | --- |
| durable writes (one fsync per write) | ~900 |
| batched writes (`--no-sync`, one fsync at the end) | ~350 000 |
| point reads after a flush | ~600 000 |
| reads of absent keys (Bloom filter, no disk touched) | ~3 000 000 |

The durable number is a property of the disk, not of this code: it is one
fsync per write, and that is what a fsync costs. Everything else is the
tree doing its job — the Bloom filter answers an absent key without ever
reading a block, and the block cache means a workload with locality pays
one checksum per block instead of one per key.

Two of those numbers moved a long way during development, and both
diagnoses came from a profile rather than a guess: `crc32` was 66 % of
every point read (the standard library computed it bitwise, eight rounds
per byte — now table-driven, [upstreamed to
`std/deflate`](../../stdlib/std/deflate.nu)), and after that the block
cache took the remaining per-read verification out of scans and any
workload with locality. Point reads went from 47 500/s to ~600 000/s.

## CLI

```
lsmdb [OPTIONS] <command> [args]

  put <key> <value>     store a value (durable when it returns)
  get <key>             print the value; exit 1 if the key is absent
  del <key>             delete a key
  scan                  print key<TAB>value for a range, in order
  load                  bulk import key<TAB>value lines from stdin
  flush                 force the memtable out into a table
  compact               merge every table into one, dropping dead data
  stats                 tables, entries, bytes, sequence
  bench                 measure writes/s and reads/s on this machine

  -d, --dir DIR         database directory ($LSMDB_DIR, else ./lsmdb)
  -f, --from KEY        scan: start key (inclusive)
  -t, --to KEY          scan: end key (exclusive)
  -l, --limit N         scan: stop after N rows
      --at SEQ          read as of sequence number SEQ (a snapshot)
  -r, --raw             get: no trailing newline after the value
      --no-sync         do not fsync each write (faster, unsafe)
```

Exit codes: `0` fine, `1` key absent, `2` usage, `3` database error
(corruption, I/O). Values are read and written as raw bytes, so binary
values round-trip byte for byte.

## Library

```nurl
$ `lsmdb.nu`

: !*Lsm String opened ( lsm_open `/var/db/things` )
?? opened {
    T db → {
        : ( Vec u ) k ( bytes_from_str `hello` )
        : ( Vec u ) v ( bytes_from_str `world` )
        ?? ( lsm_put db k v ) { T _ → {} F e → { ( string_free e ) } }

        ?? ( lsm_get db k ) {
            T g → { ? == . g found 1 { ( write_bytes . g val ) } {} ( lsm_get_free g ) }
            F e → { ( string_free e ) }
        }
        ( vec_free [u] k ) ( vec_free [u] v )
        ( lsm_close db )
    }
    F e → { ( string_free e ) }
}
```

| | |
| --- | --- |
| `( lsm_open dir )` | `!*Lsm String` — creates, recovers and replays |
| `( lsm_put db key val )` | `!v String` — durable on return |
| `( lsm_del db key )` | `!v String` |
| `( lsm_get db key )` | `!LsmGet String` — `.found`, `.seq`, `.val` |
| `( lsm_get_at db key snap )` | as of sequence `snap` |
| `( lsm_scan db from to limit snap )` | `!LsmScan String` — ordered, half-open |
| `( lsm_flush db )` / `( lsm_compact db )` | `!i String` |
| `( lsm_stats db )` | `LsmStats` |
| `( lsm_set_durable db F )` | batch mode; pair with `( lsm_sync db )` |
| `( lsm_close db )` | |

Keys and values are `( Vec u )` — arbitrary bytes, borrowed by the store
(it copies what it keeps). The empty key is rejected.

## Tests

```sh
./tests/lsmdb_test.sh      # 30 behaviour + crash + corruption assertions
./tests/stress_test.sh     # differential: the database vs a sorted text file
```

Every CLI command in the test runs as its own process, so persistence and
recovery are exercised by construction. The two that matter most:
`lsmdb_test.sh` appends a half record to the log (what `kill -9` during an
append leaves behind) and flips a byte inside a table, and asserts that
the first loses exactly one write while the second is refused as an error.
`stress_test.sh` feeds identical writes to the database and to a plain
sorted text file across four tables, deletes a seventh of the keys,
overwrites another seventh, compacts, and diffs the entire contents —
which checks ordering, versioning, tombstones, block boundaries, the
index search, the Bloom filter and the merge all at once, rather than
whatever properties someone thought to name.

## License

MIT OR Apache-2.0
