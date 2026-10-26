// packages/nurldb/src/wal.nu — the write-ahead log, with group commit.
//
// Every change to a page is described by a log record before the page
// changes, and a page goes to disk only once the log is durable up to
// the record that changed it last (the buffer pool asks wal_flush_to
// first). A crash then loses no committed work: recovery replays the log
// over the data file from the last checkpoint (recovery.nu).
//
// The file:
//
//   0   "NDBLOG01"
//   8   u64 base   the LSN of byte 16
//   16  records:   [u32 len][u32 crc32(payload)][payload]…
//
// A record's LSN is the log position just past its end, so "record r is
// durable" is `lsn(r) <= flushed`. LSNs grow for the life of the
// database: a log that is reset after a checkpoint starts again at the
// LSN it had reached (`base`), so a page's LSN never compares against a
// smaller log position than the one that changed it.
//
// Threads. Any number of threads append at once: the pending bytes live
// in an RwLocked buffer, taken exclusively for the copy of one record.
// One flusher thread owns the file's tail: it is woken through a channel,
// takes the whole buffer at once, writes it, makes it durable (fdatasync)
// and publishes how far the log is durable (an Atomic), then wakes every
// committer waiting on a condition variable. Twenty committers arriving
// while one write is in flight share the next one: that is group commit,
// and it is why a commit costs one device round trip however many
// threads commit at once.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/deflate.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/pfile.nu`

: i WAL_HDR 16
: i WAL_REC_HDR 8

// What is appended but not yet written: `buf` holds the log from `start`.
: LogBuf {
    ( Vec u ) buf
    i start
}

: WalImpl {
    PFile file
    ( RwLocked LogBuf ) pend
    // The log position past the last appended record.
    Atomic next
    // How far the log is durable.
    Atomic flushed
    // The LSN of byte 16 of the file.
    i base
    Mutex mu
    Cond cv
    ( Channel i ) wake
    Thread flusher
    b sync
    // Writes the flusher made (each one a device round trip when `sync`).
    Atomic writes
}

: Wal { ( Arc WalImpl ) a }

@ Wal_share Wal w → Wal { ^ @ Wal { ( arc_clone [WalImpl] . w a ) } }

@ Wal_drop sink Wal w → v {}

// What the flusher thread works with: the parts of the log it shares
// with the appenders (handles — every copy is the same object).
: WalTail {
    PFile file
    ( RwLocked LogBuf ) pend
    Atomic flushed
    Mutex mu
    Cond cv
    i base
    b sync
    Atomic writes
}

@ __wal_hdr_bytes i base → ( Vec u ) {
    : ( Vec u ) h ( vec_zeroed [u] WAL_HDR )
    : ( Slice u ) s ( slice_from_vec [u] h )
    ( slice_put_u64_le s 0 5786951493436523342 )  // "NDBLOG01" little-endian
    ( slice_put_u64_le s 8 base )
    ^ h
}

// What the flusher takes out of the buffer: the bytes and where they go.
: LogPend { ( Vec u ) data i start }

// The pending bytes, taken: an empty buffer is left in their place, so
// appenders carry on while they are written. The write guard goes when
// this returns.
@ __wal_take ( RwLocked LogBuf ) pend → LogPend {
    : ( WGuard LogBuf ) g ( rw_write [LogBuf] pend )
    ^ ( wguard_apply [LogBuf LogPend] g \ inout LogBuf b → LogPend {
        : i st . b start
        : ( Vec u ) out ( mem_replace [( Vec u )] . b buf ( vec_with_cap [u] 65536 ) )
        = . b start + st ( vec_len [u] out )
        ^ @ LogPend { out st }
    } )
}

// Write out what is pending, make it durable, publish how far it reaches
// and wake the committers waiting for it. The flusher thread's one step.
@ __wal_write_out WalTail t → b {
    : LogPend p ( __wal_take . t pend )
    : i n ( vec_len [u] . p data )
    ? == n 0 { ^ T } {}
    : i off + WAL_HDR - . p start . t base
    ?? ( pfile_write_at . t file ( slice_from_vec [u] . p data ) off ) { T _ → {} F _ → { ^ F } }
    ? . t sync { ?? ( pfile_datasync . t file ) { T _ → {} F _ → { ^ F } } } {}
    ( atomic_add . t writes 1 )
    ( atomic_store . t flushed + . p start n )
    ( mutex_lock . t mu )
    ( cond_broadcast . t cv )
    ( mutex_unlock . t mu )
    ^ T
}

// The flusher thread: a write per wake-up, however many arrived since the
// last one. A closed channel is the signal to write what is left and stop.
@ __wal_flusher WalTail t ( Channel i ) wake → v {
    : ~ b going T
    ~ going {
        ?? ( chan_recv [i] wake ) {
            T _ → {}
            F → { = going F }
        }
        // (Everyone who asked while the last write was in flight is served
        // by this one.)
        : ~ b more T
        ~ more { ?? ( chan_try_recv [i] wake ) { T _ → {} F → { = more F } } }
        ? ! ( __wal_write_out t ) { ( nurl_eprintln `nurldb: the write-ahead log could not be written` ) } {}
    }
}

// Open the log at `path` (created when absent). `sync` false skips the
// fdatasync of each flush: faster, and a crash may lose the last commits
// (never corrupt anything: the log is still written before the pages).
@ wal_open s path b sync → !Wal String {
    : PFile f ?? ( pfile_open path PFILE_CREATE ) { T h → h F _ → { ^ @ !Wal String { F ( string_from `nurldb: cannot open the log` ) } } }
    : i size ?? ( pfile_size f ) { T n → n F _ → 0 }
    : ~ i base 1
    ? < size WAL_HDR {
        : ( Vec u ) h ( __wal_hdr_bytes 1 )
        ?? ( pfile_write_at f ( slice_from_vec [u] h ) 0 ) { T _ → {} F _ → { ^ @ !Wal String { F ( string_from `nurldb: cannot write the log header` ) } } }
        ?? ( pfile_set_len f WAL_HDR ) { T _ → {} F _ → {} }
    } {
        : ( Vec u ) h ?? ( pfile_read_vec_at f 0 WAL_HDR ) { T v → v F _ → ( vec_new [u] ) }
        : ( Slice u ) hs ( slice_from_vec [u] h )
        ? | < ( vec_len [u] h ) WAL_HDR != ( slice_u64_le hs 0 ) 5786951493436523342 { ^ @ !Wal String { F ( string_from `nurldb: not a nurldb log` ) } } {}
        = base ( slice_u64_le hs 8 )
    }
    : i end + base - ? < size WAL_HDR WAL_HDR size WAL_HDR
    : ( RwLocked LogBuf ) pend ( rw_new [LogBuf] @ LogBuf { ( vec_with_cap [u] 65536 ) end } )
    : Atomic flushed ( atomic_new end )
    : Mutex mu ( mutex_new )
    : Cond cv ( cond_new )
    : ( Channel i ) wake ( chan_new [i] )
    : Atomic writes ( atomic_new 0 )
    : WalTail tail @ WalTail { ( mem_dup f ) ( mem_dup pend ) ( mem_dup flushed ) ( mem_dup mu ) ( mem_dup cv ) base sync ( mem_dup writes ) }
    : Thread th ?? ( thread_spawn \ → v { ( __wal_flusher tail wake ) } ) { T t → t F _ → { ^ @ !Wal String { F ( string_from `nurldb: cannot start the log flusher` ) } } }
    ^ @ !Wal String { T @ Wal { ( arc_new [WalImpl] @ WalImpl { f pend ( atomic_new end ) flushed base mu cv wake th sync writes } ) } }
}

// Append one record; its LSN (the log position past it) comes back. The
// record is in the log buffer, not yet durable: wal_flush_to makes it so.
@ wal_append Wal w ( Slice u ) payload → i {
    : WalImpl x ( arc_get [WalImpl] . w a )
    : i n ( slice_len [u] payload )
    : i crc ( crc32_slice payload )
    : ( WGuard LogBuf ) g ( rw_write [LogBuf] . x pend )
    : LogBuf b ( wguard_get [LogBuf] g )
    // (Read before the pushes: growing the buffer through `buf` ends the
    // other borrows of the guard's value, `b` among them.)
    : i start . b start
    : ( Vec u ) buf . b buf
    ( vec_push_word_u8 buf n 4 F )
    ( vec_push_word_u8 buf crc 4 F )
    : i at ( vec_len [u] buf )
    ( vec_resize_zeroed [u] buf + at n )
    ( slice_copy [u] ( slice_window [u] ( slice_from_vec [u] buf ) at n ) payload )
    : i lsn + start ( vec_len [u] buf )
    ( atomic_store . x next lsn )
    ^ lsn
}

// Block until the log is durable up to `lsn` (a commit record's, a page's
// last change). Many callers at once are served by one write.
@ wal_flush_to Wal w i lsn → v {
    : WalImpl x ( arc_get [WalImpl] . w a )
    ? <= lsn ( atomic_load . x flushed ) { ^ } {}
    ( chan_send [i] . x wake lsn )
    ( mutex_lock . x mu )
    ~ < ( atomic_load . x flushed ) lsn { ( cond_wait . x cv . x mu ) }
    ( mutex_unlock . x mu )
}

// Everything appended so far, durable.
@ wal_flush_all Wal w → v { ( wal_flush_to w ( wal_next w ) ) }

@ wal_next Wal w → i { ^ ( atomic_load . ( arc_get [WalImpl] . w a ) next ) }

@ wal_flushed Wal w → i { ^ ( atomic_load . ( arc_get [WalImpl] . w a ) flushed ) }

// How many writes the flusher has made: with many committers, far fewer
// than commits.
@ wal_writes Wal w → i { ^ ( atomic_load . ( arc_get [WalImpl] . w a ) writes ) }

// Stop the flusher thread after it has written what is pending. The log
// handle stays usable for reading; nothing more may be appended.
@ wal_close Wal w → v {
    : WalImpl x ( arc_get [WalImpl] . w a )
    ( chan_close [i] . x wake )
    : i _j ( thread_join . x flusher )
}

// ── replay ─────────────────────────────────────────────────────────────

// Every intact record from `from` (an LSN at a record boundary) on, in
// order: `f` gets each record's LSN and its payload (a view, valid for the
// call). Replay stops at the first record that is short, too long or fails
// its checksum — a crash in the middle of an append — and the log end it
// reached comes back: the caller truncates the torn tail there
// (wal_truncate_to), or every later append would hide behind it.
@ wal_replay s path i from ( @ v i ( Slice u ) ) f → !i String {
    : PFile pf ?? ( pfile_open path PFILE_READ ) { T h → h F _ → { ^ @ !i String { F ( string_from `nurldb: cannot open the log` ) } } }
    : i size ?? ( pfile_size pf ) { T n → n F _ → 0 }
    ? < size WAL_HDR { ^ @ !i String { T from } } {}
    : ( Vec u ) h ?? ( pfile_read_vec_at pf 0 WAL_HDR ) { T v → v F _ → ( vec_new [u] ) }
    : i base ( slice_u64_le ( slice_from_vec [u] h ) 8 )
    : ~ i pos ? < from base WAL_HDR + WAL_HDR - from base
    ? > pos size { ^ @ !i String { T + base - size WAL_HDR } } {}
    // The whole tail, read once: replay is sequential.
    : ( Vec u ) all ?? ( pfile_read_vec_at pf pos - size pos ) { T v → v F _ → ( vec_new [u] ) }
    : ( Slice u ) av ( slice_from_vec [u] all )
    : i total ( vec_len [u] all )
    : ~ i k 0
    ~ <= + k WAL_REC_HDR total {
        : i n ( slice_u32_le av k )
        : i crc ( slice_u32_le av + k 4 )
        ? > + + k WAL_REC_HDR n total { break } {}
        : ( Slice u ) body ( slice_window [u] av + k WAL_REC_HDR n )
        ? != crc ( crc32_slice body ) { break } {}
        = k + + k WAL_REC_HDR n
        ( f + base - + pos k WAL_HDR body )
    }
    ^ @ !i String { T + base - + pos k WAL_HDR }
}

// Cut the log back to `lsn` (the end replay reached): a torn record past
// it is dropped, and the next append lands right after the last intact
// one.
@ wal_truncate_to s path i lsn → !v String {
    : PFile pf ?? ( pfile_open path PFILE_RW ) { T h → h F _ → { ^ @ !v String { F ( string_from `nurldb: cannot open the log` ) } } }
    : ( Vec u ) h ?? ( pfile_read_vec_at pf 0 WAL_HDR ) { T v → v F _ → ( vec_new [u] ) }
    ? < ( vec_len [u] h ) WAL_HDR { ^ @ !v String { T 0 } } {}
    : i base ( slice_u64_le ( slice_from_vec [u] h ) 8 )
    ?? ( pfile_set_len pf + WAL_HDR - lsn base ) { T _ → {} F _ → { ^ @ !v String { F ( string_from `nurldb: cannot truncate the log` ) } } }
    ?? ( pfile_sync pf ) { T _ → {} F _ → {} }
    ^ @ !v String { T 0 }
}

// Start the log afresh at `lsn` (after a checkpoint made every record
// before it unnecessary): the file holds a header whose base is `lsn`
// and nothing else. The log must not be open for appending.
@ wal_reset s path i lsn → !v String {
    : PFile pf ?? ( pfile_open path PFILE_TRUNC ) { T h → h F _ → { ^ @ !v String { F ( string_from `nurldb: cannot reset the log` ) } } }
    : ( Vec u ) h ( __wal_hdr_bytes lsn )
    ?? ( pfile_write_at pf ( slice_from_vec [u] h ) 0 ) { T _ → {} F _ → { ^ @ !v String { F ( string_from `nurldb: cannot write the log header` ) } } }
    ?? ( pfile_sync pf ) { T _ → {} F _ → {} }
    ^ @ !v String { T 0 }
}
