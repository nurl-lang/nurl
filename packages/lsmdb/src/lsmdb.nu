// packages/lsmdb/src/lsmdb.nu — the store: an LSM tree that survives
// being killed.
//
// Writes go to the write-ahead log (fsynced), then into the memtable.
// When the memtable fills it is flushed into an immutable SSTable and the
// log is reset. Reads consult the memtable first, then the tables from
// newest to oldest, and stop at the first version they find — including a
// tombstone, which means "deleted here, look no further". Compaction
// merges every table into one, keeping only the newest version of each
// key and dropping tombstones.
//
// Crash safety comes from the ORDER of those steps, not from hoping:
//
//   put      → log append → fsync → memtable      (acknowledged = durable)
//   flush    → write table → fsync → publish manifest (rename+dir fsync)
//              → reset log
//   compact  → write merged table → fsync → publish manifest → unlink old
//
// Every crash point in that sequence lands on a state the next open()
// reads correctly. A table written but not yet named by the manifest is
// an orphan file and its writes are still in the log; a manifest naming a
// table whose writes are ALSO still in the log replays them into the
// memtable at their original sequence numbers, where they shadow the
// identical versions in the table. Nothing is lost, nothing is doubled.
//
// Sequence numbers are the other half of the design: every write gets
// one, versions of a key sort newest-first, and a read at sequence S sees
// the database exactly as it was after write S — a snapshot, for free.
//
//   ( lsm_open dir )                     → !Lsm String
//   ( lsm_put db key val )               → !v String
//   ( lsm_del db key )                   → !v String
//   ( lsm_get db key )                   → !LsmGet String
//   ( lsm_get_at db key snap )           → !LsmGet String   time travel
//   ( lsm_scan db from to limit snap )   → !LsmScan String
//   ( lsm_flush db ) / ( lsm_compact db ) → !i String
//   ( lsm_stats db )                     → LsmStats
//   ( lsm_close db )                     → v   early release (optional)
//
// An Lsm is a handle: every copy is the same open database, and the last
// owner closes it — the log, every table file, the memtable. LsmGet and
// LsmScan are plain values; nothing here is released by hand.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `memtable.nu`
$ `sst.nu`
$ `wal.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`

: i LSM_MEMLIMIT 4194304  // 4 MiB of memtable before an auto-flush

: LsmImpl {
    String dir
    String walpath
    String manpath
    MemTable mem
    ( Vec String ) names  // table file names, NEWEST FIRST
    ( Vec SstReader ) tables  // parallel to names
    Wal wal
    i seq
    i nextfile
    i memlimit
    i durable
    i flushes
    i compactions
    i filtered  // gets a table's filter answered without a read
}

: Lsm { ( Locked LsmImpl ) l }

@ Lsm_share Lsm h → Lsm { ^ @ Lsm { ( Locked_share [LsmImpl] . h l ) } }

@ Lsm_drop sink Lsm h → v {}

: LsmGet {
    i found
    i seq
    ( Vec u ) val
}

: LsmStats {
    i tables
    i entries
    i memcount
    i membytes
    i seq
    i filebytes
    i blockreads
    i filtered
}

// Let go of `g` now rather than at the end of its owner's scope.
@ lsm_get_free sink LsmGet g → v {}

@ __lsm_err s what → String { ^ ( string_from what ) }

// ── paths ───────────────────────────────────────────────────────────

@ __lsm_path inout LsmImpl db s name → String {
    ^ ( path_join ( string_data . db dir ) name )
}

// Zero-padded so the table files sort the way they were created.
@ __lsm_table_name i n → String {
    : String s ( string_with_cap 16 )
    : String digits ( string_with_cap 16 )
    ( string_push_int digits n )
    : ~ i pad - 6 ( string_len digits )
    ~ > pad 0 { ( string_push_char s 48 ) = pad - pad 1 }
    ( string_push_str s ( string_data digits ) )
    ( string_push_str s `.sst` )
    ^ s
}

// ── manifest ────────────────────────────────────────────────────────
//
// The manifest is the only thing that decides which tables exist. It is
// replaced by rename, never edited in place, so a reader either sees the
// whole old list or the whole new one.

@ __lsm_manifest_write inout LsmImpl db → !v String {
    : String tmp ( __lsm_path db `MANIFEST.tmp` )
    : String body ( string_with_cap 256 )
    ( string_push_str body `lsmdb-manifest v1
seq ` )
    ( string_push_int body . db seq )
    ( string_push_str body `
next ` )
    ( string_push_int body . db nextfile )
    ( string_push_char body 10 )
    : ~ i k 0
    ~ < k ( vec_len [String] . db names ) {
        ?? ( vec_get [String] . db names k ) {
            T nm → {
                ( string_push_str body `sst ` )
                ( string_push_str body ( string_data nm ) )
                ( string_push_char body 10 )
            }
            F → {}
        }
        = k + k 1
    }
    : ~ b ok T
    ?? ( file_create ( string_data tmp ) ) {
        T f → {
            : ( Vec u ) bytes ( bytes_from_str ( string_data body ) )
            ?? ( file_write_chunk f bytes ) { T _ → {} F _ → { = ok F } }
            ?? ( file_sync f ) { T _ → {} F _ → { = ok F } }
            ( file_close f )
        }
        F _ → { = ok F }
    }
    ? ok {} {
        ^ @ !v String { F ( __lsm_err `lsmdb: cannot write the manifest` ) }
    }
    ?? ( fs_rename ( string_data tmp ) ( string_data . db manpath ) ) {
        T _ → {}
        F _ → { = ok F }
    }
    ? ok {} { ^ @ !v String { F ( __lsm_err `lsmdb: cannot publish the manifest` ) } }
    // The rename itself has to reach the disk, or a crash can leave the
    // table on disk with the old manifest still naming the world.
    ?? ( dir_sync ( string_data . db dir ) ) { T _ → {} F _ → {} }
    ^ @ !v String { T 0 }
}

// The rest of a manifest line after its `keyword ` prefix.
@ __lsm_after String ln i n → String {
    : i len ( string_len ln )
    ? >= n len { ^ ( string_new ) } {}
    ^ ( string_substr ln n - len n )
}

@ __lsm_manifest_read inout LsmImpl db → !v String {
    ? ( file_exists ( string_data . db manpath ) ) {} { ^ @ !v String { T 0 } }
    : !String IoErr rr ( read_file ( string_data . db manpath ) )
    : ~ String text ( string_new )
    ?? rr { T s → { = text s } F _ → {
            ^ @ !v String { F ( __lsm_err `lsmdb: cannot read the manifest` ) } } }
    : ( Vec String ) lines ( string_split text `
` )
    : ~ b bad F
    : ~ i k 0
    ~ < k ( vec_len [String] lines ) {
        ?? ( vec_get [String] lines k ) {
            T ln → {
                ? == k 0 {
                    ? ( string_starts_with ln `lsmdb-manifest v1` ) {} { = bad T }
                } {
                    ? ( string_starts_with ln `seq ` ) {
                        : String rest ( __lsm_after ln 4 )
                        = . db seq ( nurl_str_to_int ( string_data rest ) )
                    } {
                        ? ( string_starts_with ln `next ` ) {
                            : String rest ( __lsm_after ln 5 )
                            = . db nextfile ( nurl_str_to_int ( string_data rest ) )
                        } {
                            ? ( string_starts_with ln `sst ` ) {
                                ( vec_push [String] . db names ( __lsm_after ln 4 ) )
                            } {}
                        }
                    }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ? bad { ^ @ !v String { F ( __lsm_err `lsmdb: not an lsmdb manifest` ) } } {}
    ^ @ !v String { T 0 }
}

// ── open / close ────────────────────────────────────────────────────

@ lsm_open s dir → !Lsm String {
    ?? ( dir_create_all dir ) {
        T _ → {}
        F _ → {
            : String msg ( string_from `lsmdb: cannot create database directory ` )
            ( string_push_str msg dir )
            ^ @ !Lsm String { F msg }
        }
    }
    // The state first: every early return below lets go of it, and with
    // it of whatever was opened so far (the log is not open yet).
    : ~ LsmImpl db @ LsmImpl { ( string_from dir ) ( path_join dir `WAL` ) ( path_join dir `MANIFEST` ) ( mt_new 0 )
        ( vec_new [String] ) ( vec_new [SstReader] ) ( wal_none ) 0 1 LSM_MEMLIMIT 1 0 0 0 }

    ?? ( __lsm_manifest_read db ) {
        T _ → {}
        F e → { ^ @ !Lsm String { F e } }
    }
    // Open every named table. A table the manifest names but the
    // directory does not have is a broken database, not a warning.
    : ~ i k 0
    ~ < k ( vec_len [String] . db names ) {
        ?? ( vec_get [String] . db names k ) {
            T nm → {
                : String full ( __lsm_path db ( string_data nm ) )
                ?? ( sst_open ( string_data full ) ) {
                    T r → { ( vec_push [SstReader] . db tables r ) }
                    F e → { ^ @ !Lsm String { F e } }
                }
            }
            F → {}
        }
        = k + k 1
    }

    // Replay whatever the log still holds on top of the tables.
    : !WalStat String wr ( wal_replay ( string_data . db walpath ) . db mem )
    ?? wr {
        T st → {
            ? > . st maxseq . db seq { = . db seq . st maxseq } {}
            // A crash mid-append leaves a torn record at the tail. It was
            // never acknowledged, so replay dropped it — but the bytes
            // have to GO, or the next replay would stop at them again and
            // every write made from now on would be stranded behind them.
            ? == . st truncated 1 {
                ?? ( wal_truncate ( string_data . db walpath ) . st bytes ) {
                    T _ → {}
                    F e → { ^ @ !Lsm String { F e } }
                }
            } {}
        }
        F e → { ^ @ !Lsm String { F e } }
    }
    : !Wal String wo ( wal_open ( string_data . db walpath ) )
    ?? wo {
        T w → { = . db wal w }
        F e → { ^ @ !Lsm String { F e } }
    }
    ^ @ !Lsm String { T @ Lsm { ( locked_new [LsmImpl] db ) } }
}

// Let go of `db` now rather than at the end of its owner's scope. The
// last owner closes the database: the log, every table, the memtable.
@ lsm_close sink Lsm db → v {}

@ lsm_seq Lsm db__h → i {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : i __res ( __lsm_seq_in db )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_seq_in inout LsmImpl db → i {
    ^ . db seq
}

// Force everything written so far to the device. Only needed after
// running with durability switched off — a bulk import that wants one
// fsync at the end instead of one per row.
@ lsm_sync Lsm db__h → !v String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !v String __res ( __lsm_sync_in db )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_sync_in inout LsmImpl db → !v String {
    ^ ( wal_sync . db wal )
}

@ lsm_set_durable Lsm db__h b on → v {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    ( __lsm_set_durable_in db on )
    ( locked_restore [LsmImpl] . db__h l db )
}

@ __lsm_set_durable_in inout LsmImpl db b on → v {
    = . db durable ? on 1 0
}

@ lsm_set_memlimit Lsm db__h i n → v {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    ( __lsm_set_memlimit_in db n )
    ( locked_restore [LsmImpl] . db__h l db )
}

@ __lsm_set_memlimit_in inout LsmImpl db i n → v {
    = . db memlimit ? > n 1024 n 1024
}

// ── writes ──────────────────────────────────────────────────────────

@ __lsm_write inout LsmImpl db ( Vec u ) key ( Vec u ) val i kind → !v String {
    = . db seq + . db seq 1
    : i seq . db seq
    ?? ( wal_append . db wal key val seq kind ) { T _ → {} F e → { ^ @ !v String { F e } } }
    ? == . db durable 1 {
        ?? ( wal_sync . db wal ) { T _ → {} F e → { ^ @ !v String { F e } } }
    } {}
    ( mt_put . db mem key val seq kind )
    ? >= ( mt_bytes . db mem ) . db memlimit {
        ?? ( __lsm_flush db ) { T _ → {} F e → { ^ @ !v String { F e } } }
    } {}
    ^ @ !v String { T 0 }
}

@ lsm_put Lsm db__h ( Vec u ) key ( Vec u ) val → !v String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !v String __res ( __lsm_put_in db key val )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_put_in inout LsmImpl db ( Vec u ) key ( Vec u ) val → !v String {
    ? == ( vec_len [u] key ) 0 {
        ^ @ !v String { F ( __lsm_err `lsmdb: the empty key is not a key` ) }
    } {}
    ^ ( __lsm_write db key val MT_PUT )
}

@ lsm_del Lsm db__h ( Vec u ) key → !v String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !v String __res ( __lsm_del_in db key )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_del_in inout LsmImpl db ( Vec u ) key → !v String {
    : ( Vec u ) empty ( vec_new [u] )
    ^ ( __lsm_write db key empty MT_DEL )
}

// ── reads ───────────────────────────────────────────────────────────

@ lsm_get Lsm db__h ( Vec u ) key → !LsmGet String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !LsmGet String __res ( __lsm_get_in db key )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_get_in inout LsmImpl db ( Vec u ) key → !LsmGet String {
    ^ ( __lsm_get_at db key . db seq )
}

// The read path in full: memtable, then tables newest to oldest. The
// FIRST version found wins, and a tombstone counts as found — that is
// what stops an older table's stale value from resurrecting a deleted key.
@ lsm_get_at Lsm db__h ( Vec u ) key i snap → !LsmGet String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !LsmGet String __res ( __lsm_get_at_in db key snap )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_get_at_in inout LsmImpl db ( Vec u ) key i snap → !LsmGet String {
    ^ ( __lsm_get_at db key snap )
}

@ __lsm_get_at inout LsmImpl db ( Vec u ) key i snap → !LsmGet String {
    : i node ( mt_find . db mem key snap )
    ? != node 0 {
        ? == ( mt_kind . db mem node ) MT_DEL {
            ^ @ !LsmGet String { T @ LsmGet { 0 0 ( vec_new [u] ) } }
        } {}
        ^ @ !LsmGet String { T @ LsmGet { 1 ( mt_seq . db mem node ) ( mt_val . db mem node ) } }
    } {}
    : ~ i k 0
    : i n ( vec_len [SstReader] . db tables )
    : i kh ( lsm_key_hash ( slice_from_vec [u] key ) )
    ~ < k n {
        ?? ( vec_get [SstReader] . db tables k ) {
            T r → {
                : !SstHit String hr ( sst_get_hashed r key kh snap )
                ?? hr {
                    T hit → {
                        ? == . hit found -1 { = . db filtered + . db filtered 1 } {}
                        ? == . hit found 1 {
                            ? == . hit kind MT_DEL {
                                ^ @ !LsmGet String { T @ LsmGet { 0 0 ( vec_new [u] ) } }
                            } {}
                            ^ @ !LsmGet String { T @ LsmGet { 1 . hit seq . hit val } }
                        } {}
                    }
                    F e → { ^ @ !LsmGet String { F e } }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ !LsmGet String { T @ LsmGet { 0 0 ( vec_new [u] ) } }
}

// ── merged iteration ────────────────────────────────────────────────
//
// One ordered view over the memtable and every table at once. Each
// source is already sorted by (key ascending, sequence descending), so
// the merge is a repeated "which head sorts first" — and because the
// sequence half of that order puts newer versions first, the FIRST time
// a key appears is always its newest visible version.

: LsmIterImpl {
    i usemem
    i mnode
    ( Vec SstCursor ) curs
    // Each cursor's head as the merge last saw it: the key bytes, the
    // sequence, whether it is valid. Picking the next source compares
    // these, so a step reads every source's head without opening a
    // cursor; a cursor is opened only to move it or read its value.
    ( Vec ( Vec u ) ) hkey
    ( Vec i ) hseq
    ( Vec i ) hkind
    ( Vec i ) hvalid
    i src  // -1 memtable, >=0 cursor index, -2 exhausted
    i failed
    String err
}

@ __it_new inout LsmImpl db b usemem ( Vec u ) from i snap → LsmIterImpl {
    : ~ LsmIterImpl it @ LsmIterImpl { ? usemem 1 0 0 ( vec_new [SstCursor] ) ( vec_new [( Vec u )] ) ( vec_new [i] ) ( vec_new [i] )
        ( vec_new [i] ) -2 0 ( string_new ) }
    : b seeking > ( vec_len [u] from ) 0
    = . it mnode ? usemem ? seeking ( mt_seek . db mem from snap ) ( mt_first . db mem ) 0
    : ~ i k 0
    ~ < k ( vec_len [SstReader] . db tables ) {
        ?? ( vec_get [SstReader] . db tables k ) {
            T r → {
                : SstCursor c ( sst_cursor r )
                ? seeking { ( sc_seek c from snap ) } { ( sc_first c ) }
                : ScHead h0 ( sc_head c )
                ( vec_push [SstCursor] . it curs c )
                ( vec_push [( Vec u )] . it hkey ( vec_new [u] ) )
                ( vec_push [i] . it hseq 0 )
                ( vec_push [i] . it hkind 0 )
                ( vec_push [i] . it hvalid 0 )
                ( __it_set_head it k h0 )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ it
}

// Cursor `k` of the merge (another owner of it).
@ __it_cursor LsmIterImpl it i k → SstCursor {
    ?? ( vec_get [SstCursor] . it curs k ) {
        T c → { ^ ( SstCursor_share c ) }
        F _ → { ( nurl_panic `lsmdb: no such cursor` ) }
    }
}

// Cursor `k`'s head, as the merge keeps it (after it moved).
@ __it_set_head inout LsmIterImpl it i k sink ScHead h → v {
    ? . h failed {
        = . it failed 1
        = . it err ( sc_err ( __it_cursor it k ) )
    } {}
    : b _v ( vec_set [i] . it hvalid k ? . h valid 1 0 )
    : b _s ( vec_set [i] . it hseq k . h seq )
    : b _d ( vec_set [i] . it hkind k . h kind )
    : b _k ( vec_set [( Vec u )] . it hkey k . h key )
}

// Whether source `k`'s head sorts before the current best's: key
// ascending, the newer version first. `best` is -1 (the memtable's node
// `mnode`) or another cursor.
@ __it_before LsmIterImpl it MemTable mem i k i best → b {
    : ( Slice u ) ka ?? ( vec_get [( Vec u )] . it hkey k ) { T x → ( slice_from_vec [u] x ) F _ → { ^ F } }
    : i sa ( vec_at [i] . it hseq k )
    : ~ i c 0
    : ~ i sb 0
    ? == best -1 {
        = c ( slice_bytes_cmp ka ( mt_key_view mem . it mnode ) )
        = sb ( mt_seq mem . it mnode )
    } {
        ?? ( vec_get [( Vec u )] . it hkey best ) { T kb → { = c ( slice_bytes_cmp ka ( slice_from_vec [u] kb ) ) } F _ → { ^ F } }
        = sb ( vec_at [i] . it hseq best )
    }
    ? != c 0 { ^ < c 0 } {}
    ^ > sa sb
}

// Select the source whose head sorts first. Returns -2 when every source
// is exhausted.
@ __it_pick inout LsmIterImpl it MemTable mem → i {
    : ~ i best -2
    ? & == . it usemem 1 != . it mnode 0 { = best -1 } {}
    : ~ i k 0
    : i n ( vec_len [i] . it hvalid )
    ~ < k n {
        ? == ( vec_at [i] . it hvalid k ) 1 {
            ? | == best -2 ( __it_before it mem k best ) { = best k } {}
        } {}
        = k + k 1
    }
    = . it src best
    ^ best
}

// The selected cursor (another owner of it).
@ __it_cur LsmIterImpl it → SstCursor { ^ ( __it_cursor it . it src ) }

@ __it_advance inout LsmIterImpl it MemTable mem → v {
    ? == . it src -1 { = . it mnode ( mt_next mem . it mnode ) } {
        ? >= . it src 0 { ( __it_set_head it . it src ( sc_next_head ( __it_cur it ) ) ) } {}
    }
}

// Key of the currently selected head, owned. A cursor's key leaves the
// merge's copy of its head (no second copy): the caller reads it once a
// step, and the advance that follows refreshes the head anyway.
@ __it_key inout LsmIterImpl it MemTable mem → ( Vec u ) {
    ? == . it src -1 { ^ ( mt_key mem . it mnode ) } {}
    ?? ( vec_replace [( Vec u )] . it hkey . it src ( vec_new [u] ) ) { T x → { ^ x } F → { ^ ( vec_new [u] ) } }
}

@ __it_val LsmIterImpl it MemTable mem → ( Vec u ) {
    ? == . it src -1 { ^ ( mt_val mem . it mnode ) } {}
    ^ ( sc_val ( __it_cur it ) )
}

@ __it_seq LsmIterImpl it MemTable mem → i {
    ? == . it src -1 { ^ ( mt_seq mem . it mnode ) } {}
    ^ ( vec_at [i] . it hseq . it src )
}

@ __it_kind LsmIterImpl it MemTable mem → i {
    ? == . it src -1 { ^ ( mt_kind mem . it mnode ) } {}
    ^ ( vec_at [i] . it hkind . it src )
}

// ── scan ────────────────────────────────────────────────────────────

: LsmScan {
    ( Vec u ) keys
    ( Vec i ) koff
    ( Vec i ) klen
    ( Vec u ) vals
    ( Vec i ) voff
    ( Vec i ) vlen
    i count
}

// Let go of `s` now rather than at the end of its owner's scope.
@ lsm_scan_free sink LsmScan s → v {}

@ lsm_scan_count LsmScan s → i { ^ . s count }

@ lsm_scan_key LsmScan s i k → ( Vec u ) {
    ^ ( _mt_slice . s keys ?? ( vec_get [i] . s koff k ) { T x → x F _ → 0 }
    ?? ( vec_get [i] . s klen k ) { T x → x F _ → 0 } )
}

@ lsm_scan_val LsmScan s i k → ( Vec u ) {
    ^ ( _mt_slice . s vals ?? ( vec_get [i] . s voff k ) { T x → x F _ → 0 }
    ?? ( vec_get [i] . s vlen k ) { T x → x F _ → 0 } )
}

// Every live key in [from, to) as of `snap`, in order. An empty `from`
// starts at the beginning; an empty `to` runs to the end; limit <= 0
// means no limit.
@ lsm_scan Lsm db__h ( Vec u ) from ( Vec u ) to i limit i snap → !LsmScan String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !LsmScan String __res ( __lsm_scan_in db from to limit snap )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_scan_in inout LsmImpl db ( Vec u ) from ( Vec u ) to i limit i snap → !LsmScan String {
    : ~ LsmIterImpl it ( __it_new db T from snap )
    : ( Vec u ) keys ( vec_new [u] )
    : ( Vec i ) koff ( vec_new [i] )
    : ( Vec i ) klen ( vec_new [i] )
    : ( Vec u ) vals ( vec_new [u] )
    : ( Vec i ) voff ( vec_new [i] )
    : ( Vec i ) vlen ( vec_new [i] )
    : ~ i count 0
    : ~ b stop F
    : ~ b failed F
    : ~ String err ( string_new )
    : ~ ( Vec u ) prev ( vec_new [u] )
    : ~ b haveprev F
    : b bounded > ( vec_len [u] to ) 0

    ~ ! stop {
        : i src ( __it_pick it . db mem )
        ? == . it failed 1 {
            = failed T = err ( string_from ( string_data . it err ) )
            = stop T
        } {
            ? == src -2 { = stop T } {
                : ( Vec u ) key ( __it_key it . db mem )
                : i seq ( __it_seq it . db mem )
                : b samekey & haveprev == 0 ( lsm_bytes_cmp key prev )
                ? & bounded >= ( lsm_bytes_cmp key to ) 0 { = stop T } {
                    // an older version of a key already emitted, or a
                    // version newer than the snapshot: skip it
                    ? | samekey > seq snap {} {
                        // first visible version of this key
                        ? == ( __it_kind it . db mem ) MT_PUT {
                            : ( Vec u ) val ( __it_val it . db mem )
                            ( vec_push [i] koff ( vec_len [u] keys ) )
                            ( vec_push [i] klen ( vec_len [u] key ) )
                            ( vec_extend [u] keys key )
                            ( vec_push [i] voff ( vec_len [u] vals ) )
                            ( vec_push [i] vlen ( vec_len [u] val ) )
                            ( vec_extend [u] vals val )
                            = count + count 1
                            ? & > limit 0 >= count limit { = stop T } {}
                        } {}
                        = prev key
                        = haveprev T
                    }
                }
                ? stop {} { ( __it_advance it . db mem ) }
            }
        }
    }
    ? failed { ^ @ !LsmScan String { F err } } {}
    ^ @ !LsmScan String { T @ LsmScan { keys koff klen vals voff vlen count } }
}

// ── flush ───────────────────────────────────────────────────────────

// Turn the memtable into a table. EVERY version is written, not just the
// newest — the memtable is the newest data in the database, and throwing
// away its history here would silently break snapshot reads that the
// tables themselves still support.
@ lsm_flush Lsm db__h → !i String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !i String __res ( __lsm_flush_in db )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_flush_in inout LsmImpl db → !i String {
    ^ ( __lsm_flush db )
}

@ __lsm_flush inout LsmImpl db → !i String {
    : i n ( mt_count . db mem )
    ? == n 0 { ^ @ !i String { T 0 } } {}
    : String name ( __lsm_table_name . db nextfile )
    : String full ( __lsm_path db ( string_data name ) )
    : !SstWriter String cw ( sst_create ( string_data full ) )
    : SstWriter w ?? cw {
        T x → x
        F e → { ^ @ !i String { F e } }
    }

    : ~ i node ( mt_first . db mem )
    : ~ b failed F
    : ~ String err ( string_new )
    ~ & != node 0 ! failed {
        : ( Vec u ) k ( mt_key . db mem node )
        : ( Vec u ) v ( mt_val . db mem node )
        ?? ( sst_add w k v ( mt_seq . db mem node ) ( mt_kind . db mem node ) ) {
            T _ → {}
            F e → { = failed T = err e }
        }
        = node ( mt_next . db mem node )
    }
    : !i String fin ( sst_finish w )
    ?? fin { T _ → {} F e → { ? failed {} { = failed T = err e } } }
    ? failed {
        ?? ( file_delete ( string_data full ) ) { T _ → {} F _ → {} }
        ^ @ !i String { F err }
    } {}

    // The table is on disk and fsynced. Only now may the manifest name it.
    ?? ( sst_open ( string_data full ) ) {
        T r → {
            ( vec_insert [String] . db names 0 name )
            : b _ok ( vec_insert [SstReader] . db tables 0 r )
        }
        F e → { ^ @ !i String { F e } }
    }
    = . db nextfile + . db nextfile 1
    ?? ( __lsm_manifest_write db ) { T _ → {} F e → { ^ @ !i String { F e } } }

    // Published — the log's job is done and the memtable can go.
    ?? ( wal_reset ( string_data . db walpath ) ) { T _ → {} F e → { ^ @ !i String { F e } } }
    ?? ( wal_reopen . db wal ( string_data . db walpath ) ) { T _ → {} F e → { ^ @ !i String { F e } } }
    // A store through the pointer does not drop what the field held: let
    // go of the old memtable first.
    ( mt_free . db mem )
    = . db mem ( mt_new 0 )
    = . db flushes + . db flushes 1
    ^ @ !i String { T n }
}

// ── compaction ──────────────────────────────────────────────────────

// Merge every source into `w`, keeping only the newest version of each
// key and dropping tombstones. Returns the entries kept. The merge
// iterator — and with it every cursor's share of a table — is gone when
// this returns, so the old tables close as soon as the store lets them go.
@ __lsm_merge_into inout LsmImpl db SstWriter w → !i String {
    : ( Vec u ) nokey ( vec_new [u] )
    : ~ LsmIterImpl it ( __it_new db F nokey . db seq )
    : ~ ( Vec u ) prev ( vec_new [u] )
    : ~ b haveprev F
    : ~ i kept 0
    : ~ b stop F
    : ~ b failed F
    : ~ String err ( string_new )

    ~ ! stop {
        : i src ( __it_pick it . db mem )
        ? == . it failed 1 {
            = failed T = err ( string_from ( string_data . it err ) )
            = stop T
        } {
            ? == src -2 { = stop T } {
                : ( Vec u ) key ( __it_key it . db mem )
                : b samekey & haveprev == 0 ( lsm_bytes_cmp key prev )
                ? samekey {} {
                    ? == ( __it_kind it . db mem ) MT_PUT {
                        : ( Vec u ) val ( __it_val it . db mem )
                        ?? ( sst_add w key val ( __it_seq it . db mem ) MT_PUT ) {
                            T _ → {}
                            F e → { = failed T = stop T = err e }
                        }
                        = kept + kept 1
                    } {}
                    = prev key
                    = haveprev T
                }
                ? stop {} { ( __it_advance it . db mem ) }
            }
        }
    }
    ? failed { ^ @ !i String { F err } } {}
    ^ @ !i String { T kept }
}

// Merge every table into one, keeping only the newest version of each
// key and dropping tombstones. This is where space actually comes back:
// overwritten values and deleted keys stop existing.
//
// It also throws history away, deliberately — a snapshot read older than
// this point can no longer be served, exactly as in LevelDB. Compaction
// is a choice to trade the past for space.
@ lsm_compact Lsm db__h → !i String {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : !i String __res ( __lsm_compact_in db )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_compact_in inout LsmImpl db → !i String {
    : i ntables ( vec_len [SstReader] . db tables )
    ? < ntables 1 { ^ @ !i String { T 0 } } {}

    : String name ( __lsm_table_name . db nextfile )
    : String full ( __lsm_path db ( string_data name ) )
    : !SstWriter String cw ( sst_create ( string_data full ) )
    : SstWriter w ?? cw {
        T x → x
        F e → { ^ @ !i String { F e } }
    }

    : ~ i kept 0
    : ~ b failed F
    : ~ String err ( string_new )
    ?? ( __lsm_merge_into db w ) { T n → { = kept n } F e → { = failed T = err e } }

    : !i String fin ( sst_finish w )
    ?? fin { T _ → {} F e → { ? failed {} { = failed T = err e } } }
    ? failed {
        ?? ( file_delete ( string_data full ) ) { T _ → {} F _ → {} }
        ^ @ !i String { F err }
    } {}

    // Take the old tables out of the live set before publishing, but do
    // not unlink them until the new manifest is on disk: a crash in
    // between must find either the old list or the new one, both intact.
    : ( Vec String ) old ( vec_new [String] )
    : ~ i k 0
    ~ < k ( vec_len [String] . db names ) {
        ?? ( vec_get [String] . db names k ) { T s → { ( vec_push [String] old s ) } F → {} }
        = k + k 1
    }
    ( vec_clear [String] . db names )
    // the readers close their files as they go
    ( vec_clear [SstReader] . db tables )

    ?? ( sst_open ( string_data full ) ) {
        T r → {
            ( vec_push [String] . db names name )
            ( vec_push [SstReader] . db tables r )
        }
        F e → { ^ @ !i String { F e } }
    }
    = . db nextfile + . db nextfile 1
    ?? ( __lsm_manifest_write db ) {
        T _ → {}
        F e → { ^ @ !i String { F e } }
    }

    : ~ i j 0
    ~ < j ( vec_len [String] old ) {
        ?? ( vec_get [String] old j ) {
            T nm → {
                : String p ( __lsm_path db ( string_data nm ) )
                ?? ( file_delete ( string_data p ) ) { T _ → {} F _ → {} }
            }
            F → {}
        }
        = j + j 1
    }
    = . db compactions + . db compactions 1
    ^ @ !i String { T kept }
}

// ── stats ───────────────────────────────────────────────────────────

@ lsm_stats Lsm db__h → LsmStats {
    : ~ LsmImpl db ( locked_take [LsmImpl] . db__h l )
    : LsmStats __res ( __lsm_stats_in db )
    ( locked_restore [LsmImpl] . db__h l db )
    ^ __res
}

@ __lsm_stats_in inout LsmImpl db → LsmStats {
    : ~ i entries 0
    : ~ i filebytes 0
    : ~ i reads 0
    : i filtered . db filtered
    : ~ i k 0
    ~ < k ( vec_len [SstReader] . db tables ) {
        ?? ( vec_get [SstReader] . db tables k ) {
            T r → {
                = entries + entries ( sst_entries r )
                = filebytes + filebytes ( sst_filesize r )
                = reads + reads ( sst_reads r )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ LsmStats {
        ( vec_len [SstReader] . db tables )
        entries
        ( mt_count . db mem )
        ( mt_bytes . db mem )
        . db seq
        filebytes
        reads
        filtered
    }
}
