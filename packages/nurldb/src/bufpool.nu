// packages/nurldb/src/bufpool.nu — the buffer pool.
//
// A fixed number of page frames shared by every thread. A page is reached
// only through a guard:
//
//   ( pool_read p pid )    → PageRead    shared: any number of readers
//   ( pool_write p pid )   → PageWrite   exclusive
//   ( pool_new_page p type ) → PageWrite a page appended to the file
//   ( page_bytes r ) / ( page_bytes_mut w ) → ( Slice u )
//
// A guard pins its frame (the frame is not evicted while it is held) and
// latches it (a read or a write latch on the frame's RwLocked). The bytes
// are a view held to the guard: the borrow checker ends the view where
// the guard goes, so hand-over-hand traversal — take the child's guard,
// then let the parent's go — is safe by construction, and a read guard's
// view is frozen (RGuard is `% Frozen`, and a struct holding one lends
// frozen views too): nothing can write through it. A guard is released
// by its drop, on every way out, a panic included (the drop journal).
//
// Concurrency. The page table (pid → frame) is an RwLocked: a lookup that
// finds its page takes it shared, so hits on different pages never wait
// for each other; only a miss takes it exclusively. A miss evicts by the
// clock algorithm: a frame nobody pins whose reference bit is clear. A
// clean victim's write latch is taken (it is uncontended: nothing pins
// the frame) before the page table is let go, so the page it is about to
// hold cannot be read before it is loaded. A dirty victim is written back
// first — pinned, outside the table lock, after the log is durable up to
// the page's LSN (the write-ahead rule) — and the miss starts over.
//
// Writing a page out happens under a READ latch (readers carry on): the
// page's checksum goes into a copy, which is what reaches the disk.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/pfile.nu`
$ `page.nu`
$ `wal.nu`

: Frame {
    ( Vec u ) data
    // The page it holds, -1 none.
    i pid
}

// pid → frame, open addressing with linear probing: keys -1 empty. A
// deletion shifts the entries after it back (no tombstones), so a table
// that churns forever — every eviction deletes one page and inserts
// another — never fills up with dead slots a lookup must walk past.
: PidMap {
    ( Vec i ) keys
    ( Vec i ) vals
    i mask
    // The clock hand, kept with the table it is moved under.
    i hand
}

: PoolImpl {
    PFile file
    Wal wal
    ( Vec ( RwLocked Frame ) ) frames
    ( Vec Atomic ) pins
    ( Vec Atomic ) dirty
    ( Vec Atomic ) refb
    ( RwLocked PidMap ) map
    // Pages in the file: the next page appended gets this number.
    Atomic npages
    i nframes
    Atomic hits
    Atomic misses
    Atomic writes
    // The log position of the last checkpoint: a page last changed before
    // it gets a full-page image at its next change (heap.nu log_page).
    Atomic redo
    // Recovery: a page that fails its check is a torn write, rebuilt by
    // redo from its full-page image — read as empty, not refused.
    Atomic recovering
}

: BufPool { ( Arc PoolImpl ) a }

@ BufPool_share BufPool p → BufPool { ^ @ BufPool { ( arc_clone [PoolImpl] . p a ) } }

@ BufPool_drop sink BufPool p → v {}

// ── the page table ─────────────────────────────────────────────────────

@ __pm_hash i pid i mask → i { ^ & ^^ * pid -7046029254386353131 >> * pid -7046029254386353131 29 mask }

@ __pm_find PidMap m i pid → i {
    : ~ i k ( __pm_hash pid . m mask )
    ~ T {
        : i key ( vec_at [i] . m keys k )
        ? == key pid { ^ ( vec_at [i] . m vals k ) } {}
        ? == key -1 { ^ -1 } {}
        = k & + k 1 . m mask
    }
    ^ -1
}

@ __pm_put PidMap m i pid i frame → v {
    : ~ i k ( __pm_hash pid . m mask )
    ~ T {
        : i key ( vec_at [i] . m keys k )
        ? | == key pid == key -1 {
            ( vec_put [i] . m keys k pid )
            ( vec_put [i] . m vals k frame )
            ^
        } {}
        = k & + k 1 . m mask
    }
}

@ __pm_del PidMap m i pid → v {
    : i mask . m mask
    : ~ i k ( __pm_hash pid mask )
    ~ != ( vec_at [i] . m keys k ) pid {
        ? == ( vec_at [i] . m keys k ) -1 { ^ } {}
        = k & + k 1 mask
    }
    // Backward shift: every entry after the hole that may move into it
    // (its home is not cyclically within (hole, j]) does.
    : ~ i hole k
    : ~ i j k
    ~ T {
        = j & + j 1 mask
        : i kj ( vec_at [i] . m keys j )
        ? == kj -1 { break } {}
        : i home ( __pm_hash kj mask )
        : b stays ? <= hole j & < hole home <= home j | < hole home <= home j
        ? ! stays {
            ( vec_put [i] . m keys hole kj )
            ( vec_put [i] . m vals hole ( vec_at [i] . m vals j ) )
            = hole j
        } {}
    }
    ( vec_put [i] . m keys hole -1 )
}

// ── guards ─────────────────────────────────────────────────────────────

: PageRead {
    ( RGuard Frame ) g
    Atomic pin
    i pid
}

: PageWrite {
    ( WGuard Frame ) g
    Atomic pin
    Atomic dirty
    i pid
}

// Unpinned when the guard goes; its latch goes with its field right after.
% Drop PageRead { @ drop PageRead r → v { ( atomic_sub . r pin 1 ) } }

% Drop PageWrite {
    @ drop PageWrite w → v {
        ( atomic_store . w dirty 1 )
        ( atomic_sub . w pin 1 )
    }
}

// The page's bytes: a frozen view, held to the guard.
@ page_bytes PageRead r → ( Slice u ) { ^ ( slice_from_vec [u] . ( rguard_get [Frame] . r g ) data ) }

@ page_bytes_mut PageWrite w → ( Slice u ) { ^ ( slice_from_vec [u] . ( wguard_get [Frame] . w g ) data ) }

@ page_read_pid PageRead r → i { ^ . r pid }

@ page_write_pid PageWrite w → i { ^ . w pid }

// ── the pool ───────────────────────────────────────────────────────────

// A pool of `nframes` frames over the data file `file`, writing back
// under the log `wal`.
@ pool_new PFile file Wal wal i nframes → BufPool {
    : ( Vec ( RwLocked Frame ) ) frames ( vec_with_cap [( RwLocked Frame )] nframes )
    : ( Vec Atomic ) pins ( vec_with_cap [Atomic] nframes )
    : ( Vec Atomic ) dirty ( vec_with_cap [Atomic] nframes )
    : ( Vec Atomic ) refb ( vec_with_cap [Atomic] nframes )
    : ~ i k 0
    ~ < k nframes {
        ( vec_push [( RwLocked Frame )] frames ( rw_new [Frame] @ Frame { ( vec_zeroed [u] PAGE_SIZE ) -1 } ) )
        ( vec_push [Atomic] pins ( atomic_new 0 ) )
        ( vec_push [Atomic] dirty ( atomic_new 0 ) )
        ( vec_push [Atomic] refb ( atomic_new 0 ) )
        = k + k 1
    }
    : ~ i cap 16
    ~ < cap * 2 nframes { = cap * cap 2 }
    : ( Vec i ) keys ( vec_new [i] )
    : ( Vec i ) vals ( vec_new [i] )
    = k 0
    ~ < k cap { ( vec_push [i] keys -1 ) ( vec_push [i] vals -1 ) = k + k 1 }
    : i size ?? ( pfile_size file ) { T n → n F _ → 0 }
    ^ @ BufPool { ( arc_new [PoolImpl] @ PoolImpl {
            file wal frames pins dirty refb
            ( rw_new [PidMap] @ PidMap { keys vals - cap 1 0 } )
            ( atomic_new / + size - PAGE_SIZE 1 PAGE_SIZE )
            nframes ( atomic_new 0 ) ( atomic_new 0 ) ( atomic_new 0 )
            ( atomic_new 0 ) ( atomic_new 0 )
        } ) }
}

@ pool_redo BufPool p → i { ^ ( atomic_load . ( arc_get [PoolImpl] . p a ) redo ) }

@ pool_set_redo BufPool p i lsn → v { ( atomic_store . ( arc_get [PoolImpl] . p a ) redo lsn ) }

@ pool_set_recovering BufPool p b on → v { ( atomic_store . ( arc_get [PoolImpl] . p a ) recovering ? on 1 0 ) }

// The file holds at least `n` pages (recovery: a page the log names that
// a crash kept from reaching the file).
@ pool_ensure_npages BufPool p i n → v { : i _m ( atomic_max . ( arc_get [PoolImpl] . p a ) npages n ) }

@ pool_npages BufPool p → i { ^ ( atomic_load . ( arc_get [PoolImpl] . p a ) npages ) }

@ pool_hits BufPool p → i { ^ ( atomic_load . ( arc_get [PoolImpl] . p a ) hits ) }

@ pool_misses BufPool p → i { ^ ( atomic_load . ( arc_get [PoolImpl] . p a ) misses ) }

@ pool_writes BufPool p → i { ^ ( atomic_load . ( arc_get [PoolImpl] . p a ) writes ) }

// Where `pid` sits, pinned — or -1. The table is held shared: lookups of
// any number of threads go together.
@ __pool_lookup_pin PoolImpl p i pid → i {
    : ( RGuard PidMap ) g ( rw_read [PidMap] . p map )
    : i f ( __pm_find ( rguard_get [PidMap] g ) pid )
    ? >= f 0 {
        ( atomic_add ( vec_at [Atomic] . p pins f ) 1 )
        ( atomic_store ( vec_at [Atomic] . p refb f ) 1 )
    } {}
    ^ f
}

// What a miss decided under the exclusive table lock: the frame it pinned,
// and either the frame's write latch (a clean victim, now the page's) or
// the old page to write back first.
: Claim {
    i frame
    // > 0: a dirty victim was pinned for write-back; the miss starts over.
    b flush
    // -1: the page was already there (another thread installed it).
    ? ( WGuard Frame ) g
}

@ __pool_claim PoolImpl p i pid → Claim {
    : ( WGuard PidMap ) mg ( rw_write [PidMap] . p map )
    ^ ( wguard_apply [PidMap Claim] mg \ inout PidMap m → Claim {
        // Installed by another thread since the shared lookup?
        : i f ( __pm_find m pid )
        ? >= f 0 {
            ( atomic_add ( vec_at [Atomic] . p pins f ) 1 )
            ^ @ Claim { f F @ ?( WGuard Frame ) { F } }
        } {}
        : i n . p nframes
        : ~ i tries 0
        ~ < tries * 3 n {
            : i v . m hand
            = . m hand % + v 1 n
            = tries + tries 1
            ? == ( atomic_load ( vec_at [Atomic] . p pins v ) ) 0 {
                : Atomic rb ( vec_at [Atomic] . p refb v )
                ? != ( atomic_swap rb 0 ) 0 { continue } {}
                ? != ( atomic_load ( vec_at [Atomic] . p dirty v ) ) 0 {
                    ( atomic_add ( vec_at [Atomic] . p pins v ) 1 )
                    ^ @ Claim { v T @ ?( WGuard Frame ) { F } }
                } {}
                ?? ( rw_try_write [Frame] ( vec_at [( RwLocked Frame )] . p frames v ) ) {
                    T g → {
                        : i old . ( wguard_get [Frame] g ) pid
                        ? >= old 0 { ( __pm_del m old ) } {}
                        ( __pm_put m pid v )
                        ( atomic_add ( vec_at [Atomic] . p pins v ) 1 )
                        ( atomic_store ( vec_at [Atomic] . p refb v ) 1 )
                        ^ @ Claim { v F @ ?( WGuard Frame ) { T g } }
                    }
                    F → {}
                }
            } {}
        }
        ^ @ Claim { -1 F @ ?( WGuard Frame ) { F } }
    } )
}

// Write frame `f` out if it is dirty: the log first (the write-ahead
// rule), then the page — a copy carrying its checksum — under a read
// latch, so readers of the page carry on. The dirty flag is cleared
// before the write: a writer that changes the page after it waits for the
// read latch to go and sets the flag again.
@ __pool_flush_frame PoolImpl p i f → v {
    : Atomic d ( vec_at [Atomic] . p dirty f )
    : ( RGuard Frame ) g ( rw_read [Frame] ( vec_at [( RwLocked Frame )] . p frames f ) )
    : Frame fr ( rguard_get [Frame] g )
    ? | < . fr pid 0 == ( atomic_swap d 0 ) 0 { ^ } {}
    : ( Slice u ) view ( slice_from_vec [u] . fr data )
    ( wal_flush_to . p wal ( pg_lsn view ) )
    : ( Vec u ) copy ( slice_to_vec [u] view )
    : ( Slice u ) cs ( slice_from_vec [u] copy )
    ( pg_set_crc cs ( pg_checksum cs ) )
    ?? ( pfile_write_at . p file cs * . fr pid PAGE_SIZE ) {
        T _ → { ( atomic_add . p writes 1 ) }
        F _ → {
            ( atomic_store d 1 )
            ( panic_with ( string_concat ( string_from `nurldb: cannot write page ` ) ( string_from ( nurl_str_int . fr pid ) ) ) )
        }
    }
}

// Load page `pid` into the frame whose write latch `g` holds: read it
// (and check it) or, for a page past the end of the file, zero it.
@ __pool_load PoolImpl p ( WGuard Frame ) g i pid b fresh → b {
    : ( Slice u ) view ( slice_from_vec [u] . ( wguard_get [Frame] g ) data )
    : ~ b ok T
    ? fresh { ( pg_init view pid PT_FREE ) } {
        ?? ( pfile_read_at . p file view * pid PAGE_SIZE ) {
            T got → {
                ? < got PAGE_SIZE {
                    // (past the end: a page appended but never written)
                    ( pg_init view pid PT_FREE )
                } { = ok ( pg_verify view pid ) }
            }
            F _ → { = ok F }
        }
    }
    ( wguard_update [Frame] g \ inout Frame fr → v { = . fr pid pid } )
    ^ ok
}

// Pin page `pid` into a frame, loading it on a miss; the frame comes
// back. `fresh`: the page is new (appended), so nothing is read.
@ __pool_pin PoolImpl p i pid b fresh → i {
    ~ T {
        : i f ( __pool_lookup_pin p pid )
        ? >= f 0 { ( atomic_add . p hits 1 ) ^ f } {}
        : Claim c ( __pool_claim p pid )
        ? < . c frame 0 { ( panic `nurldb: the buffer pool is exhausted — every frame is pinned` ) } {}
        ? . c flush {
            ( __pool_flush_frame p . c frame )
            ( atomic_sub ( vec_at [Atomic] . p pins . c frame ) 1 )
            continue
        } {}
        ?? . c g {
            T g → {
                ( atomic_add . p misses 1 )
                : b loaded ( __pool_load p g pid fresh )
                ? & ! loaded != 0 ( atomic_load . p recovering ) {
                    // Torn: empty until redo puts its image back.
                    ( pg_init ( slice_from_vec [u] . ( wguard_get [Frame] g ) data ) pid PT_FREE )
                } {}
                ? & ! loaded == 0 ( atomic_load . p recovering ) {
                    // Not a page: give the frame back before saying so.
                    ( wguard_update [Frame] g \ inout Frame fr → v { = . fr pid -1 } )
                    {
                        : ( WGuard PidMap ) mg ( rw_write [PidMap] . p map )
                        ( wguard_update [PidMap] mg \ inout PidMap m → v { ( __pm_del m pid ) } )
                    }
                    ( atomic_sub ( vec_at [Atomic] . p pins . c frame ) 1 )
                    ( panic_with ( string_concat ( string_from `nurldb: page ` ) ( string_concat ( string_from ( nurl_str_int pid ) ) ( string_from ` is damaged (bad checksum or page number)` ) ) ) )
                } {}
            }
            F → {}
        }
        ^ . c frame
    }
    ^ -1
}

@ pool_read BufPool p i pid → PageRead {
    : PoolImpl x ( arc_get [PoolImpl] . p a )
    : i f ( __pool_pin x pid F )
    : ( RGuard Frame ) g ( rw_read [Frame] ( vec_at [( RwLocked Frame )] . x frames f ) )
    ^ @ PageRead { g ( mem_dup ( vec_at [Atomic] . x pins f ) ) pid }
}

@ pool_write BufPool p i pid → PageWrite {
    : PoolImpl x ( arc_get [PoolImpl] . p a )
    : i f ( __pool_pin x pid F )
    : ( WGuard Frame ) g ( rw_write [Frame] ( vec_at [( RwLocked Frame )] . x frames f ) )
    ^ @ PageWrite { g ( mem_dup ( vec_at [Atomic] . x pins f ) ) ( mem_dup ( vec_at [Atomic] . x dirty f ) ) pid }
}

// A page appended to the file: a zeroed frame with the header of `type`,
// write-latched. Its number is the next one; the file grows when it is
// written back.
@ pool_new_page BufPool p i type → PageWrite {
    : PoolImpl x ( arc_get [PoolImpl] . p a )
    : i pid ( atomic_add . x npages 1 )
    : i f ( __pool_pin x pid T )
    : ( WGuard Frame ) g ( rw_write [Frame] ( vec_at [( RwLocked Frame )] . x frames f ) )
    ( pg_init ( slice_from_vec [u] . ( wguard_get [Frame] g ) data ) pid type )
    ^ @ PageWrite { g ( mem_dup ( vec_at [Atomic] . x pins f ) ) ( mem_dup ( vec_at [Atomic] . x dirty f ) ) pid }
}

// Write every dirty page out (a checkpoint's first half). Pages changed
// while it runs are written by the next one.
@ pool_flush_all BufPool p → v {
    : PoolImpl x ( arc_get [PoolImpl] . p a )
    : ~ i f 0
    ~ < f . x nframes {
        ? != ( atomic_load ( vec_at [Atomic] . x dirty f ) ) 0 {
            ( atomic_add ( vec_at [Atomic] . x pins f ) 1 )
            ( __pool_flush_frame x f )
            ( atomic_sub ( vec_at [Atomic] . x pins f ) 1 )
        } {}
        = f + f 1
    }
}

// Dirty frames right now (racy: a statistic).
@ pool_dirty_count BufPool p → i {
    : PoolImpl x ( arc_get [PoolImpl] . p a )
    : ~ i n 0
    : ~ i f 0
    ~ < f . x nframes {
        ? != ( atomic_load ( vec_at [Atomic] . x dirty f ) ) 0 { = n + n 1 } {}
        = f + f 1
    }
    ^ n
}
