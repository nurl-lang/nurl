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
//   ( lsm_open dir )                     → !*Lsm String
//   ( lsm_put db key val )               → !v String
//   ( lsm_del db key )                   → !v String
//   ( lsm_get db key )                   → !LsmGet String
//   ( lsm_get_at db key snap )           → !LsmGet String   time travel
//   ( lsm_scan db from to limit snap )   → !LsmScan String
//   ( lsm_flush db ) / ( lsm_compact db ) → !i String
//   ( lsm_stats db )                     → LsmStats
//   ( lsm_close db )

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `memtable.nu`
$ `sst.nu`
$ `wal.nu`

: i LSM_MEMLIMIT 4194304  // 4 MiB of memtable before an auto-flush

: Lsm {
    String dir
    String walpath
    String manpath
    * MemTable mem
    ( Vec String ) names  // table file names, NEWEST FIRST
    ( Vec * SstReader ) tables  // parallel to names
    * Wal wal
    i seq
    i nextfile
    i memlimit
    i durable
    i flushes
    i compactions
}

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

@ lsm_get_free LsmGet g → v { ( vec_free [u] . g val ) }

@ __lsm_err s what → String { ^ ( string_from what ) }

// ── paths ───────────────────────────────────────────────────────────

@ __lsm_path * Lsm db s name → String {
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
    ( string_free digits )
    ( string_push_str s `.sst` )
    ^ s
}

// ── manifest ────────────────────────────────────────────────────────
//
// The manifest is the only thing that decides which tables exist. It is
// replaced by rename, never edited in place, so a reader either sees the
// whole old list or the whole new one.

@ __lsm_manifest_write * Lsm db → !v String {
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
            ( vec_free [u] bytes )
        }
        F _ → { = ok F }
    }
    ( string_free body )
    ? ok {} {
        ( string_free tmp )
        ^ @ !v String { F ( __lsm_err `lsmdb: cannot write the manifest` ) }
    }
    ?? ( fs_rename ( string_data tmp ) ( string_data . db manpath ) ) {
        T _ → {}
        F _ → { = ok F }
    }
    ( string_free tmp )
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

@ __lsm_manifest_read * Lsm db → !v String {
    ? ( file_exists ( string_data . db manpath ) ) {} { ^ @ !v String { T 0 } }
    : !String IoErr rr ( read_file ( string_data . db manpath ) )
    : ~ String text ( string_new )
    ?? rr { T s → { ( string_free text ) = text s } F _ → {
            ^ @ !v String { F ( __lsm_err `lsmdb: cannot read the manifest` ) } } }
    : ( Vec String ) lines ( string_split text `
` )
    ( string_free text )
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
                        ( string_free rest )
                    } {
                        ? ( string_starts_with ln `next ` ) {
                            : String rest ( __lsm_after ln 5 )
                            = . db nextfile ( nurl_str_to_int ( string_data rest ) )
                            ( string_free rest )
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
    ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
    ? bad { ^ @ !v String { F ( __lsm_err `lsmdb: not an lsmdb manifest` ) } } {}
    ^ @ !v String { T 0 }
}

// ── open / close ────────────────────────────────────────────────────

@ lsm_open s dir → !*Lsm String {
    ?? ( dir_create_all dir ) {
        T _ → {}
        F _ → {
            : String msg ( string_from `lsmdb: cannot create database directory ` )
            ( string_push_str msg dir )
            ^ @ !*Lsm String { F msg }
        }
    }
    : *Lsm db # *Lsm ( nurl_alloc Z Lsm )
    = . db dir ( string_from dir )
    = . db walpath ( path_join dir `WAL` )
    = . db manpath ( path_join dir `MANIFEST` )
    = . db mem ( mt_new 0 )
    = . db names ( vec_new [String] )
    = . db tables ( vec_new [* SstReader] )
    = . db seq 0
    = . db nextfile 1
    = . db memlimit LSM_MEMLIMIT
    = . db durable 1
    = . db flushes 0
    = . db compactions 0

    ?? ( __lsm_manifest_read db ) {
        T _ → {}
        F e → { ( __lsm_free db ) ^ @ !*Lsm String { F e } }
    }
    // Open every named table. A table the manifest names but the
    // directory does not have is a broken database, not a warning.
    : ~ i k 0
    ~ < k ( vec_len [String] . db names ) {
        : ~ String nm ( string_new )
        ?? ( vec_get [String] . db names k ) { T s → { ( string_free nm ) = nm s } F → {} }
        : String full ( __lsm_path db ( string_data nm ) )
        : !*SstReader String orr ( sst_open ( string_data full ) )
        ( string_free full )
        ?? orr {
            T r → { ( vec_push [* SstReader] . db tables r ) }
            F e → { ( __lsm_free db ) ^ @ !*Lsm String { F e } }
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
                    F e → { ( __lsm_free db ) ^ @ !*Lsm String { F e } }
                }
            } {}
        }
        F e → { ( __lsm_free db ) ^ @ !*Lsm String { F e } }
    }
    : !*Wal String wo ( wal_open ( string_data . db walpath ) )
    ?? wo {
        T w → { = . db wal w }
        F e → { ( __lsm_free db ) ^ @ !*Lsm String { F e } }
    }
    ^ @ !*Lsm String { T db }
}

// Free everything a partially-built handle may own. The wal field is the
// one that may still be unset, so it is never touched here — lsm_close
// closes it and then calls this.
@ __lsm_free * Lsm db → v {
    ( string_free . db dir )
    ( string_free . db walpath )
    ( string_free . db manpath )
    ( mt_free . db mem )
    ( vec_free_with [String] . db names \ String s → v { ( string_free s ) } )
    ( vec_free_with [* SstReader] . db tables \ * SstReader r → v { ( sst_close r ) } )
    ( nurl_free # s db )
}

@ lsm_close * Lsm db → v {
    ( wal_close . db wal )
    ( __lsm_free db )
}

@ lsm_seq * Lsm db → i { ^ . db seq }

// Force everything written so far to the device. Only needed after
// running with durability switched off — a bulk import that wants one
// fsync at the end instead of one per row.
@ lsm_sync * Lsm db → !v String { ^ ( wal_sync . db wal ) }

@ lsm_set_durable * Lsm db b on → v { = . db durable ? on 1 0 }

@ lsm_set_memlimit * Lsm db i n → v { = . db memlimit ? > n 1024 n 1024 }

// ── writes ──────────────────────────────────────────────────────────

@ __lsm_write * Lsm db ( Vec u ) key ( Vec u ) val i kind → !v String {
    = . db seq + . db seq 1
    : i seq . db seq
    ?? ( wal_append . db wal key val seq kind ) { T _ → {} F e → { ^ @ !v String { F e } } }
    ? == . db durable 1 {
        ?? ( wal_sync . db wal ) { T _ → {} F e → { ^ @ !v String { F e } } }
    } {}
    ( mt_put . db mem key val seq kind )
    ? >= ( mt_bytes . db mem ) . db memlimit {
        ?? ( lsm_flush db ) { T _ → {} F e → { ^ @ !v String { F e } } }
    } {}
    ^ @ !v String { T 0 }
}

@ lsm_put * Lsm db ( Vec u ) key ( Vec u ) val → !v String {
    ? == ( vec_len [u] key ) 0 {
        ^ @ !v String { F ( __lsm_err `lsmdb: the empty key is not a key` ) }
    } {}
    ^ ( __lsm_write db key val MT_PUT )
}

@ lsm_del * Lsm db ( Vec u ) key → !v String {
    : ( Vec u ) empty ( vec_new [u] )
    : !v String r ( __lsm_write db key empty MT_DEL )
    ( vec_free [u] empty )
    ^ r
}

// ── reads ───────────────────────────────────────────────────────────

@ lsm_get * Lsm db ( Vec u ) key → !LsmGet String {
    ^ ( lsm_get_at db key . db seq )
}

// The read path in full: memtable, then tables newest to oldest. The
// FIRST version found wins, and a tombstone counts as found — that is
// what stops an older table's stale value from resurrecting a deleted key.
@ lsm_get_at * Lsm db ( Vec u ) key i snap → !LsmGet String {
    : i node ( mt_find . db mem key snap )
    ? != node 0 {
        ? == ( mt_kind . db mem node ) MT_DEL {
            ^ @ !LsmGet String { T @ LsmGet { 0 0 ( vec_new [u] ) } }
        } {}
        ^ @ !LsmGet String { T @ LsmGet { 1 ( mt_seq . db mem node ) ( mt_val . db mem node ) } }
    } {}
    : ~ i k 0
    : i n ( vec_len [* SstReader] . db tables )
    ~ < k n {
        ?? ( vec_get [* SstReader] . db tables k ) {
            T r → {
                : !SstHit String hr ( sst_get r key snap )
                ?? hr {
                    T hit → {
                        ? == . hit found 1 {
                            ? == . hit kind MT_DEL {
                                ( sst_hit_free hit )
                                ^ @ !LsmGet String { T @ LsmGet { 0 0 ( vec_new [u] ) } }
                            } {}
                            ^ @ !LsmGet String { T @ LsmGet { 1 . hit seq . hit val } }
                        } {}
                        ( sst_hit_free hit )
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

: LsmIter {
    * MemTable mem
    i usemem
    i mnode
    ( Vec * SstCursor ) curs
    i src  // -1 memtable, >=0 cursor index, -2 exhausted
    i failed
    String err
}

@ __it_new * Lsm db b usemem ( Vec u ) from i snap → *LsmIter {
    : *LsmIter it # *LsmIter ( nurl_alloc Z LsmIter )
    = . it mem . db mem
    = . it usemem ? usemem 1 0
    = . it curs ( vec_new [* SstCursor] )
    = . it src -2
    = . it failed 0
    = . it err ( string_new )
    : b seeking > ( vec_len [u] from ) 0
    = . it mnode ? usemem ? seeking ( mt_seek . db mem from snap ) ( mt_first . db mem ) 0
    : ~ i k 0
    ~ < k ( vec_len [* SstReader] . db tables ) {
        ?? ( vec_get [* SstReader] . db tables k ) {
            T r → {
                : *SstCursor c ( sst_cursor r )
                ? seeking { ( sc_seek c from snap ) } { ( sc_first c ) }
                ( vec_push [* SstCursor] . it curs c )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ it
}

@ __it_free * LsmIter it → v {
    ( vec_free_with [* SstCursor] . it curs \ * SstCursor c → v { ( sc_free c ) } )
    ( string_free . it err )
    ( nurl_free # s it )
}

// Select the source whose head sorts first. Returns -2 when every source
// is exhausted.
@ __it_pick * LsmIter it → i {
    : ~ i best -2
    : ~ * u bp # *u 0
    : ~ i boff 0
    : ~ i blen 0
    : ~ i bseq 0
    ? & == . it usemem 1 != . it mnode 0 {
        = best -1
        = bp ( mt_kptr . it mem )
        = boff ( mt_koff . it mem . it mnode )
        = blen ( mt_klen . it mem . it mnode )
        = bseq ( mt_seq . it mem . it mnode )
    } {}
    : ~ i k 0
    ~ < k ( vec_len [* SstCursor] . it curs ) {
        ?? ( vec_get [* SstCursor] . it curs k ) {
            T c → {
                ? ( sc_failed c ) {
                    = . it failed 1
                    ( string_free . it err )
                    = . it err ( string_from ( sc_err c ) )
                } {}
                ? ( sc_valid c ) {
                    : *u cp ( sc_kptr c )
                    : i coff ( sc_koff c )
                    : i clen ( sc_klen c )
                    : i cseq ( sc_seq c )
                    : ~ b take == best -2
                    ? take {} {
                        : i cmp ( lsm_bytes_cmp_raw cp coff clen bp boff blen )
                        = take | < cmp 0 & == cmp 0 > cseq bseq
                    }
                    ? take {
                        = best k = bp cp = boff coff = blen clen = bseq cseq
                    } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    = . it src best
    ^ best
}

@ __it_advance * LsmIter it → v {
    ? == . it src -1 { = . it mnode ( mt_next . it mem . it mnode ) } {
        ? >= . it src 0 {
            ?? ( vec_get [* SstCursor] . it curs . it src ) {
                T c → { ( sc_next c ) }
                F _ → {}
            }
        } {}
    }
}

// Key of the currently selected head, as an owned copy.
@ __it_key * LsmIter it → ( Vec u ) {
    ? == . it src -1 { ^ ( mt_key . it mem . it mnode ) } {}
    ?? ( vec_get [* SstCursor] . it curs . it src ) {
        T c → { ^ ( sc_key c ) }
        F _ → { ^ ( vec_new [u] ) }
    }
}

@ __it_val * LsmIter it → ( Vec u ) {
    ? == . it src -1 { ^ ( mt_val . it mem . it mnode ) } {}
    ?? ( vec_get [* SstCursor] . it curs . it src ) {
        T c → { ^ ( sc_val c ) }
        F _ → { ^ ( vec_new [u] ) }
    }
}

@ __it_seq * LsmIter it → i {
    ? == . it src -1 { ^ ( mt_seq . it mem . it mnode ) } {}
    ^ ?? ( vec_get [* SstCursor] . it curs . it src ) { T c → ( sc_seq c ) F _ → 0 }
}

@ __it_kind * LsmIter it → i {
    ? == . it src -1 { ^ ( mt_kind . it mem . it mnode ) } {}
    ^ ?? ( vec_get [* SstCursor] . it curs . it src ) { T c → ( sc_kind c ) F _ → MT_PUT }
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

@ lsm_scan_free LsmScan s → v {
    ( vec_free [u] . s keys ) ( vec_free [i] . s koff ) ( vec_free [i] . s klen )
    ( vec_free [u] . s vals ) ( vec_free [i] . s voff ) ( vec_free [i] . s vlen )
}

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
@ lsm_scan * Lsm db ( Vec u ) from ( Vec u ) to i limit i snap → !LsmScan String {
    : *LsmIter it ( __it_new db T from snap )
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
        : i src ( __it_pick it )
        ? == . it failed 1 {
            = failed T ( string_free err ) = err ( string_from ( string_data . it err ) )
            = stop T
        } {
            ? == src -2 { = stop T } {
                : ( Vec u ) key ( __it_key it )
                : i seq ( __it_seq it )
                : b samekey & haveprev == 0 ( lsm_bytes_cmp key prev )
                ? & bounded >= ( lsm_bytes_cmp key to ) 0 { = stop T ( vec_free [u] key ) } {
                    ? | samekey > seq snap {
                        // an older version of a key already emitted, or a
                        // version newer than the snapshot: skip it
                        ( vec_free [u] key )
                    } {
                        // first visible version of this key
                        ? == ( __it_kind it ) MT_PUT {
                            : ( Vec u ) val ( __it_val it )
                            ( vec_push [i] koff ( vec_len [u] keys ) )
                            ( vec_push [i] klen ( vec_len [u] key ) )
                            ( vec_extend [u] keys key )
                            ( vec_push [i] voff ( vec_len [u] vals ) )
                            ( vec_push [i] vlen ( vec_len [u] val ) )
                            ( vec_extend [u] vals val )
                            ( vec_free [u] val )
                            = count + count 1
                            ? & > limit 0 >= count limit { = stop T } {}
                        } {}
                        ( vec_free [u] prev )
                        = prev key
                        = haveprev T
                    }
                }
                ? stop {} { ( __it_advance it ) }
            }
        }
    }
    ( vec_free [u] prev )
    ( __it_free it )
    ? failed {
        ( vec_free [u] keys ) ( vec_free [i] koff ) ( vec_free [i] klen )
        ( vec_free [u] vals ) ( vec_free [i] voff ) ( vec_free [i] vlen )
        ^ @ !LsmScan String { F err }
    } {}
    ( string_free err )
    ^ @ !LsmScan String { T @ LsmScan { keys koff klen vals voff vlen count } }
}

// ── flush ───────────────────────────────────────────────────────────

// Turn the memtable into a table. EVERY version is written, not just the
// newest — the memtable is the newest data in the database, and throwing
// away its history here would silently break snapshot reads that the
// tables themselves still support.
@ lsm_flush * Lsm db → !i String {
    : i n ( mt_count . db mem )
    ? == n 0 { ^ @ !i String { T 0 } } {}
    : String name ( __lsm_table_name . db nextfile )
    : String full ( __lsm_path db ( string_data name ) )
    : !*SstWriter String cw ( sst_create ( string_data full ) )
    : ~ * SstWriter w # *SstWriter 0
    ?? cw { T x → { = w x } F e → {
            ( string_free name ) ( string_free full )
            ^ @ !i String { F e } } }

    : ~ i node ( mt_first . db mem )
    : ~ b failed F
    : ~ String err ( string_new )
    ~ & != node 0 ! failed {
        : ( Vec u ) k ( mt_key . db mem node )
        : ( Vec u ) v ( mt_val . db mem node )
        ?? ( sst_add w k v ( mt_seq . db mem node ) ( mt_kind . db mem node ) ) {
            T _ → {}
            F e → { = failed T ( string_free err ) = err e }
        }
        ( vec_free [u] k ) ( vec_free [u] v )
        = node ( mt_next . db mem node )
    }
    : !i String fin ( sst_finish w )
    ?? fin { T _ → {} F e → { ? failed { ( string_free e ) } { = failed T ( string_free err ) = err e } } }
    ? failed {
        ?? ( file_delete ( string_data full ) ) { T _ → {} F _ → {} }
        ( string_free name ) ( string_free full )
        ^ @ !i String { F err }
    } {}
    ( string_free err )

    // The table is on disk and fsynced. Only now may the manifest name it.
    : !*SstReader String orr ( sst_open ( string_data full ) )
    ( string_free full )
    ?? orr {
        T r → {
            ( vec_insert [String] . db names 0 name )
            : b _ok ( vec_insert [* SstReader] . db tables 0 r )
        }
        F e → { ( string_free name ) ^ @ !i String { F e } }
    }
    = . db nextfile + . db nextfile 1
    ?? ( __lsm_manifest_write db ) { T _ → {} F e → { ^ @ !i String { F e } } }

    // Published — the log's job is done and the memtable can go.
    ?? ( wal_reset ( string_data . db walpath ) ) { T _ → {} F e → { ^ @ !i String { F e } } }
    ( wal_close . db wal )
    ?? ( wal_open ( string_data . db walpath ) ) {
        T nw → { = . db wal nw }
        F e → { ^ @ !i String { F e } }
    }
    ( mt_free . db mem )
    = . db mem ( mt_new 0 )
    = . db flushes + . db flushes 1
    ^ @ !i String { T n }
}

// ── compaction ──────────────────────────────────────────────────────

// Merge every table into one, keeping only the newest version of each
// key and dropping tombstones. This is where space actually comes back:
// overwritten values and deleted keys stop existing.
//
// It also throws history away, deliberately — a snapshot read older than
// this point can no longer be served, exactly as in LevelDB. Compaction
// is a choice to trade the past for space.
@ lsm_compact * Lsm db → !i String {
    : i ntables ( vec_len [* SstReader] . db tables )
    ? < ntables 1 { ^ @ !i String { T 0 } } {}

    : String name ( __lsm_table_name . db nextfile )
    : String full ( __lsm_path db ( string_data name ) )
    : !*SstWriter String cw ( sst_create ( string_data full ) )
    : ~ * SstWriter w # *SstWriter 0
    ?? cw { T x → { = w x } F e → {
            ( string_free name ) ( string_free full )
            ^ @ !i String { F e } } }

    : ( Vec u ) nokey ( vec_new [u] )
    : *LsmIter it ( __it_new db F nokey . db seq )
    : ~ ( Vec u ) prev ( vec_new [u] )
    : ~ b haveprev F
    : ~ i kept 0
    : ~ b stop F
    : ~ b failed F
    : ~ String err ( string_new )

    ~ ! stop {
        : i src ( __it_pick it )
        ? == . it failed 1 {
            = failed T ( string_free err ) = err ( string_from ( string_data . it err ) )
            = stop T
        } {
            ? == src -2 { = stop T } {
                : ( Vec u ) key ( __it_key it )
                : b samekey & haveprev == 0 ( lsm_bytes_cmp key prev )
                ? samekey { ( vec_free [u] key ) } {
                    ? == ( __it_kind it ) MT_PUT {
                        : ( Vec u ) val ( __it_val it )
                        ?? ( sst_add w key val ( __it_seq it ) MT_PUT ) {
                            T _ → {}
                            F e → { = failed T = stop T ( string_free err ) = err e }
                        }
                        ( vec_free [u] val )
                        = kept + kept 1
                    } {}
                    ( vec_free [u] prev )
                    = prev key
                    = haveprev T
                }
                ? stop {} { ( __it_advance it ) }
            }
        }
    }
    ( vec_free [u] prev )
    ( vec_free [u] nokey )
    ( __it_free it )

    : !i String fin ( sst_finish w )
    ?? fin { T _ → {} F e → { ? failed { ( string_free e ) } { = failed T ( string_free err ) = err e } } }
    ? failed {
        ?? ( file_delete ( string_data full ) ) { T _ → {} F _ → {} }
        ( string_free name ) ( string_free full )
        ^ @ !i String { F err }
    } {}
    ( string_free err )

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
    ( vec_free_with [* SstReader] . db tables \ * SstReader r → v { ( sst_close r ) } )
    = . db tables ( vec_new [* SstReader] )

    : !*SstReader String orr ( sst_open ( string_data full ) )
    ( string_free full )
    ?? orr {
        T r → {
            ( vec_push [String] . db names name )
            ( vec_push [* SstReader] . db tables r )
        }
        F e → {
            ( string_free name )
            ( vec_free_with [String] old \ String s → v { ( string_free s ) } )
            ^ @ !i String { F e }
        }
    }
    = . db nextfile + . db nextfile 1
    ?? ( __lsm_manifest_write db ) {
        T _ → {}
        F e → {
            ( vec_free_with [String] old \ String s → v { ( string_free s ) } )
            ^ @ !i String { F e }
        }
    }

    : ~ i j 0
    ~ < j ( vec_len [String] old ) {
        ?? ( vec_get [String] old j ) {
            T nm → {
                : String p ( __lsm_path db ( string_data nm ) )
                ?? ( file_delete ( string_data p ) ) { T _ → {} F _ → {} }
                ( string_free p )
            }
            F → {}
        }
        = j + j 1
    }
    ( vec_free_with [String] old \ String s → v { ( string_free s ) } )
    = . db compactions + . db compactions 1
    ^ @ !i String { T kept }
}

// ── stats ───────────────────────────────────────────────────────────

@ lsm_stats * Lsm db → LsmStats {
    : ~ i entries 0
    : ~ i filebytes 0
    : ~ i reads 0
    : ~ i filtered 0
    : ~ i k 0
    ~ < k ( vec_len [* SstReader] . db tables ) {
        ?? ( vec_get [* SstReader] . db tables k ) {
            T r → {
                = entries + entries ( sst_entries r )
                = filebytes + filebytes ( sst_filesize r )
                = reads + reads ( sst_reads r )
                = filtered + filtered ( sst_filtered r )
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ @ LsmStats {
        ( vec_len [* SstReader] . db tables )
        entries
        ( mt_count . db mem )
        ( mt_bytes . db mem )
        . db seq
        filebytes
        reads
        filtered
    }
}
