// packages/nurldb/src/ovf.nu — TEXT values kept out of line, on overflow
// pages.
//
// A tuple lives on one heap page, so a row could never be larger than a
// page. A row whose tuple would be larger than OVF_TARGET keeps its
// longest TEXT values out of line instead, longest first, until it is
// not: each such value's bytes go to a chain of overflow pages, and the
// row holds its length and the chain's first page (value.nu). A value
// can then be as long as 2^31 - 1 bytes.
//
// An overflow page (PT_OVERFLOW), after the common header:
//
//   PG_NEXT  the next page of the chain (NO_PAGE at its end)
//   PG_AUX   how many of the value's bytes this page holds
//   32       the bytes
//
// The pages of a chain are written before the tuple that names them, and
// never change after: a new version of the row writes a chain of its own.
// Each page is logged whole (R_PAGE_IMAGE), so redo rebuilds it like any
// other page, and a chain whose tuple never made it into the log — a crash
// in between, or a transaction that aborted — is left unread, as a dead
// row version is. (There is no VACUUM yet: neither is reclaimed.)
//
// A chain is written with no other latch held, one page at a time, and
// read under the read latch of the heap page whose tuple names it: a
// reader never waits for a writer of the chain, which has let go of every
// page before the tuple exists.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `page.nu`
$ `bufpool.nu`
$ `value.nu`
$ `heap.nu`

// A row whose tuple is larger than this keeps TEXT values out of line —
// a quarter of a page, so that a heap page still holds a few rows.
: i OVF_TARGET 2048

// A TEXT value no longer than this stays in its row.
: i OVF_MIN 64

// The bytes one overflow page holds.
: i OVF_CAP 8160

// Write `b` to a chain of fresh overflow pages: its first page. The last
// page is written first, so each page is written once, knowing its next.
@ ovf_write Store st ( Slice u ) b → i {
    : i n ( slice_len [u] b )
    : i npages / - + n OVF_CAP 1 OVF_CAP
    : ~ i next NO_PAGE
    : ~ i k - npages 1
    ~ >= k 0 {
        : i off * k OVF_CAP
        : i len ? < - n off OVF_CAP - n off OVF_CAP
        : PageWrite pw ( pool_new_page . st pool PT_OVERFLOW )
        : ( Slice u ) p ( page_bytes_mut pw )
        ( pg_set_next p next )
        ( pg_set_aux p len )
        ( slice_copy [u] ( slice_window [u] p PG_HDR len ) ( slice_window [u] b off len ) )
        : i _l ( log_page_image st pw )
        = next ( page_write_pid pw )
        = k - k 1
    }
    ^ next
}

// The `len` bytes of the chain that starts at `pid`, as text.
@ ovf_read Store st i pid i len → String {
    : String s ( string_new )
    : ~ i at pid
    : ~ i left len
    ~ > left 0 {
        ? == at NO_PAGE { ( panic `nurldb: a value's overflow chain ends before its bytes do` ) } {}
        : PageRead pr ( pool_read . st pool at )
        : ( Slice u ) p ( page_bytes pr )
        ? != ( pg_type p ) PT_OVERFLOW { ( panic `nurldb: a value's overflow page is not an overflow page` ) } {}
        : i n ( pg_aux p )
        ? | | <= n 0 > n OVF_CAP > n left { ( panic `nurldb: an overflow page holds a wrong number of bytes` ) } {}
        ( string_push_window s p PG_HDR n )
        = left - left n
        = at ( pg_next p )
    }
    ^ s
}

// Which TEXT columns of `row` go out of line, their chains written: the
// first page of column k's chain at k, 0 for a column kept in the row
// (empty when every column is). The longest value goes first, until the
// tuple is no larger than OVF_TARGET or no TEXT longer than OVF_MIN is
// left in the row.
@ ovf_place Store st ( Vec Value ) row → ( Vec i ) {
    : ~ i size + TH_SIZE ( row_size row )
    : ( Vec i ) ext ( vec_new [i] )
    ? <= size OVF_TARGET { ^ ext } {}
    ~ c row { ( vec_push [i] ext 0 ) }
    ~ > size OVF_TARGET {
        : ~ i best -1
        : ~ i blen OVF_MIN
        : ~ i k 0
        ~ c row {
            ?? c {
                VText s → { ? & == ( vec_at [i] ext k ) 0 > ( string_len s ) blen { = best k = blen ( string_len s ) } {} }
                _ → {}
            }
            = k + k 1
        }
        ? < best 0 { break } {}
        ? >= blen TEXT_OUT { ( panic `nurldb: a text value of 2 GiB or more` ) } {}
        : i first ?? ( vec_at [Value] row best ) { VText s → ( ovf_write st ( string_bytes s ) ) _ → 0 }
        ( vec_put [i] ext best first )
        = size - size - + 4 blen TEXT_OUT_SIZE
    }
    ^ ext
}

// The row a tuple holds, its out-of-line values read from their pages.
@ tuple_row_full Store st ( Slice u ) t ( Vec i ) types → ( Vec Value ) {
    : ~ ( Vec i ) outs ( vec_new [i] )
    : ( Vec Value ) row ( tuple_row t types outs )
    : ~ i k 0
    ~ < k ( vec_len [i] outs ) {
        ( vec_put [Value] row ( vec_at [i] outs k ) @ Value { VText ( ovf_read st ( vec_at [i] outs + k 2 ) ( vec_at [i] outs + k 1 ) ) } )
        = k + k 3
    }
    ^ row
}
