// packages/nurldb/src/heap.nu — tables as chains of slotted pages.
//
// A heap page (PT_HEAP), after the common header:
//
//   32  u16 nslots
//   34  u16 lo      the end of the slot array
//   36  u16 hi      the start of the tuple area (tuples grow down from
//                   the end of the page)
//   40  slots: u16 offset, u16 length each — offset 0 is a free slot
//
// A tuple is one version of a row (MVCC, txn.nu):
//
//    0  u64 xmin    the transaction that made it
//    8  u64 xmax    the one that deleted or superseded it (0: none yet)
//   16  u32 cmin    the command within xmin that made it, and within xmax
//   20  u32 cmax    the one that deleted it — a statement does not see its
//                   own changes (the Halloween problem)
//   24  u64 next    reserved (0)
//   32  u16 ncols
//   34  u16 flags
//   36  the row (value.nu)
//
// A TID is pid * 65536 + slot.
//
// Every change goes through the log first (logrec.nu): under the page's
// write latch the record is appended, the change applied, and the page's
// LSN set to the record's. The same functions apply the record during
// recovery (heap_redo), so redo makes exactly the page the change made.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/thread.nu`
$ `page.nu`
$ `wal.nu`
$ `bufpool.nu`
$ `logrec.nu`
$ `value.nu`

: i HP_NSLOTS 32
: i HP_LO 34
: i HP_HI 36
: i HP_SLOTS 40

: i TH_XMIN 0
: i TH_XMAX 8
: i TH_CMIN 16
: i TH_CMAX 20
: i TH_NEXT 24
: i TH_NCOLS 32
: i TH_FLAGS 34
: i TH_SIZE 36

// The pool and the log: what every logged change needs. A handle: every
// copy shares the one pool and the one log.
: Store { BufPool pool Wal wal }

@ Store_share Store s → Store { ^ @ Store { ( BufPool_share . s pool ) ( Wal_share . s wal ) } }

@ Store_drop sink Store s → v {}

@ tid_of i pid i slot → i { ^ + * pid 65536 slot }

@ tid_pid i tid → i { ^ / tid 65536 }

@ tid_slot i tid → i { ^ % tid 65536 }

// ── page operations (pure: no log, no latch) ──────────────────────────

@ hp_init ( Slice u ) p → v {
    ( slice_put_u16_le p HP_NSLOTS 0 )
    ( slice_put_u16_le p HP_LO HP_SLOTS )
    ( slice_put_u16_le p HP_HI PAGE_SIZE )
}

@ hp_nslots ( Slice u ) p → i { ^ ( slice_u16_le p HP_NSLOTS ) }

// Bytes free for one more tuple of `n` bytes (a new slot included).
@ hp_fits ( Slice u ) p i n → b {
    : i room - ( __hp_hi p ) ( slice_u16_le p HP_LO )
    ^ <= + n 4 room
}

// PAGE_SIZE itself does not fit the u16: a fresh page's hi reads as 0.
@ __hp_hi ( Slice u ) p → i { : i h ( slice_u16_le p HP_HI ) ^ ? == h 0 PAGE_SIZE h }

// Place `t` in slot `slot` (a new slot when it is nslots): what an insert
// and its redo both do, so redo builds the same page.
@ hp_place ( Slice u ) p i slot ( Slice u ) t → v {
    : i n ( slice_len [u] t )
    : i off - ( __hp_hi p ) n
    ( slice_copy [u] ( slice_window [u] p off n ) t )
    ( slice_put_u16_le p HP_HI & off 65535 )
    : i ns ( hp_nslots p )
    ? >= slot ns {
        ( slice_put_u16_le p HP_NSLOTS + slot 1 )
        ( slice_put_u16_le p HP_LO + HP_SLOTS * 4 + slot 1 )
    } {}
    ( slice_put_u16_le p + HP_SLOTS * 4 slot off )
    ( slice_put_u16_le p + + HP_SLOTS * 4 slot 2 n )
}

// The slot an insert of `n` bytes takes: the first free one, or a new one.
@ hp_pick_slot ( Slice u ) p → i {
    : i ns ( hp_nslots p )
    : ~ i k 0
    ~ < k ns {
        ? == ( slice_u16_le p + HP_SLOTS * 4 k ) 0 { ^ k } {}
        = k + k 1
    }
    ^ ns
}

// The tuple in `slot`: its bytes, or an empty window for a free slot.
@ hp_tuple ( Slice u ) p i slot → ( Slice u ) {
    ? >= slot ( hp_nslots p ) { ^ ( slice_window [u] p 0 0 ) } {}
    : i off ( slice_u16_le p + HP_SLOTS * 4 slot )
    ? == off 0 { ^ ( slice_window [u] p 0 0 ) } {}
    ^ ( slice_window [u] p off ( slice_u16_le p + + HP_SLOTS * 4 slot 2 ) )
}

@ th_xmin ( Slice u ) t → i { ^ ( slice_u64_le t TH_XMIN ) }

@ th_xmax ( Slice u ) t → i { ^ ( slice_u64_le t TH_XMAX ) }

@ th_cmin ( Slice u ) t → i { ^ ( slice_u32_le t TH_CMIN ) }

@ th_cmax ( Slice u ) t → i { ^ ( slice_u32_le t TH_CMAX ) }

@ th_next ( Slice u ) t → i { ^ ( slice_u64_le t TH_NEXT ) }

@ hp_set_x ( Slice u ) p i slot i xmax i cmax i next → v {
    : i off ( slice_u16_le p + HP_SLOTS * 4 slot )
    ( slice_put_u64_le p + off TH_XMAX xmax )
    ( slice_put_u32_le p + off TH_CMAX cmax )
    ( slice_put_u64_le p + off TH_NEXT next )
}

// A tuple's bytes for `row`, made by `xmin` in its command `cmin`.
@ tuple_build i xmin i cmin ( Vec Value ) row → ( Vec u ) {
    : i n + TH_SIZE ( row_size row )
    : ( Vec u ) t ( vec_zeroed [u] n )
    : ( Slice u ) ts ( slice_from_vec [u] t )
    ( slice_put_u64_le ts TH_XMIN xmin )
    ( slice_put_u32_le ts TH_CMIN cmin )
    ( slice_put_u16_le ts TH_NCOLS ( vec_len [Value] row ) )
    ( row_encode row ts TH_SIZE )
    ^ t
}

// The row a tuple holds.
@ tuple_row ( Slice u ) t ( Vec i ) types → ( Vec Value ) { ^ ( row_decode t TH_SIZE types ) }

// ── logged changes ─────────────────────────────────────────────────────

// Append `rec` — the change just made to the page under `pw` — and stamp
// the page with its LSN. The first change to a page since the last
// checkpoint logs the whole page instead (a full-page image, which holds
// the change): a write of the page torn by a power cut is then rebuilt by
// redo, never read back half old (db.nu).
@ log_page Store st PageWrite pw ( Vec u ) rec → i {
    ? < ( pg_lsn ( page_bytes_mut pw ) ) ( pool_redo . st pool ) { ^ ( log_page_image st pw ) } {}
    : i lsn ( wal_append . st wal ( slice_from_vec [u] rec ) )
    ( pg_set_lsn ( page_bytes_mut pw ) lsn )
    ^ lsn
}

// Log the page under `pw` whole (R_PAGE_IMAGE): a split, a compaction, a
// page's first change after a checkpoint.
@ log_page_image Store st PageWrite pw → i {
    : ( Slice u ) p ( page_bytes_mut pw )
    : ( Vec u ) r ( rec_new R_PAGE_IMAGE + 5 PAGE_SIZE )
    ( rec_u32 r ( page_write_pid pw ) )
    ( rec_bytes r p )
    : i lsn ( wal_append . st wal ( slice_from_vec [u] r ) )
    ( pg_set_lsn p lsn )
    ^ lsn
}

// A fresh heap page, logged: what a table's chain grows by.
@ heap_new_page Store st → PageWrite {
    : PageWrite pw ( pool_new_page . st pool PT_HEAP )
    : ( Slice u ) p ( page_bytes_mut pw )
    ( hp_init p )
    : ( Vec u ) r ( rec_new R_PAGE_INIT 8 )
    ( rec_u32 r ( page_write_pid pw ) )
    ( rec_u16 r PT_HEAP )
    : i _l ( log_page st pw r )
    ^ pw
}

// Link `pid`'s page to `next` (logged).
@ heap_link Store st PageWrite pw i next → v {
    ( pg_set_next ( page_bytes_mut pw ) next )
    : ( Vec u ) r ( rec_new R_LINK 10 )
    ( rec_u32 r ( page_write_pid pw ) )
    ( rec_u32 r next )
    : i _l ( log_page st pw r )
}

// Insert tuple `t` into the page under `pw` if it fits: its slot, or -1.
@ heap_put Store st PageWrite pw ( Slice u ) t → i {
    : ( Slice u ) p ( page_bytes_mut pw )
    ? ! ( hp_fits p ( slice_len [u] t ) ) { ^ -1 } {}
    : i slot ( hp_pick_slot p )
    : ( Vec u ) r ( rec_new R_HEAP_INSERT + 11 ( slice_len [u] t ) )
    ( rec_u32 r ( page_write_pid pw ) )
    ( rec_u16 r slot )
    ( rec_u32 r ( slice_len [u] t ) )
    ( rec_bytes r t )
    ( hp_place p slot t )
    : i _l ( log_page st pw r )
    ^ slot
}

// Set a version's xmax / cmax / next (logged).
@ heap_set_x Store st PageWrite pw i slot i xmax i cmax i next → v {
    ( hp_set_x ( page_bytes_mut pw ) slot xmax cmax next )
    : ( Vec u ) r ( rec_new R_HEAP_SETX 32 )
    ( rec_u32 r ( page_write_pid pw ) )
    ( rec_u16 r slot )
    ( rec_u64 r xmax )
    ( rec_u32 r cmax )
    ( rec_u64 r next )
    : i _l ( log_page st pw r )
}

// ── redo ───────────────────────────────────────────────────────────────

// Apply a page record `r` to the page `p` it names (recovery.nu has
// checked the page's LSN is below the record's).
@ heap_redo ( Slice u ) p ( Slice u ) r → v {
    : i kind ( rec_kind r )
    ? == kind R_PAGE_INIT {
        ( pg_init p ( rec_pid r ) ( slice_u16_le r 5 ) )
        ? == ( slice_u16_le r 5 ) PT_HEAP { ( hp_init p ) } {}
    } {}
    ? == kind R_HEAP_INSERT {
        : i n ( slice_u32_le r 7 )
        ( hp_place p ( slice_u16_le r 5 ) ( slice_window [u] r 11 n ) )
    } {}
    ? == kind R_HEAP_SETX {
        ( hp_set_x p ( slice_u16_le r 5 ) ( slice_u64_le r 7 ) ( slice_u32_le r 15 ) ( slice_u64_le r 19 ) )
    } {}
    ? == kind R_LINK { ( pg_set_next p ( slice_u32_le r 5 ) ) } {}
    ? == kind R_PAGE_IMAGE {
        ( slice_copy [u] p ( slice_window [u] r 5 PAGE_SIZE ) )
    } {}
}
