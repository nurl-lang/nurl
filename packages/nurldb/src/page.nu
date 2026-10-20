// packages/nurldb/src/page.nu — the on-disk page.
//
// The data file is an array of PAGE_SIZE-byte pages; page `pid` lives at
// byte pid * PAGE_SIZE. Every page starts with the same 32-byte header:
//
//   0  u64 lsn     the log sequence number of the last change applied to
//                  this page (the end of its log record): redo skips a
//                  record whose change the page already holds, and the
//                  buffer pool writes the page out only once the log is
//                  durable up to here (the write-ahead rule)
//   8  u32 pid     the page's own number, checked on every read
//  12  u16 type    PT_*
//  14  u16 flags
//  16  u32 crc     CRC-32 of the page with this field read as zero,
//                  written when the page goes to disk, checked when it
//                  comes back: a torn or corrupted page is an error,
//                  never data
//  20  u32 next    a heap page: the next page of its table; a B+tree
//                  leaf: its right sibling
//  24  u32 prev
//  28  u32 aux     type-specific
//
// A page is reached only through the buffer pool's guards (bufpool.nu):
// a read guard lends a frozen view of the bytes, a write guard a
// changeable one. These accessors take either view.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/deflate.nu`

: i PAGE_SIZE 8192

: i PG_LSN 0
: i PG_ID 8
: i PG_TYPE 12
: i PG_FLAGS 14
: i PG_CRC 16
: i PG_NEXT 20
: i PG_PREV 24
: i PG_AUX 28
: i PG_HDR 32

// Page types.
: i PT_FREE 0
: i PT_META 1
: i PT_HEAP 2
: i PT_LEAF 3
: i PT_INNER 4
: i PT_CLOG 5

// "No page": a link that leads nowhere (page 0 is the meta page, which
// nothing links to).
: i NO_PAGE 0

@ pg_lsn ( Slice u ) p → i { ^ ( slice_u64_le p PG_LSN ) }

@ pg_set_lsn ( Slice u ) p i lsn → v { ( slice_put_u64_le p PG_LSN lsn ) }

@ pg_id ( Slice u ) p → i { ^ ( slice_u32_le p PG_ID ) }

@ pg_type ( Slice u ) p → i { ^ ( slice_u16_le p PG_TYPE ) }

@ pg_next ( Slice u ) p → i { ^ ( slice_u32_le p PG_NEXT ) }

@ pg_set_next ( Slice u ) p i n → v { ( slice_put_u32_le p PG_NEXT n ) }

@ pg_prev ( Slice u ) p → i { ^ ( slice_u32_le p PG_PREV ) }

@ pg_set_prev ( Slice u ) p i n → v { ( slice_put_u32_le p PG_PREV n ) }

@ pg_aux ( Slice u ) p → i { ^ ( slice_u32_le p PG_AUX ) }

@ pg_set_aux ( Slice u ) p i n → v { ( slice_put_u32_le p PG_AUX n ) }

// A fresh page of `type`: zeroes, then the header.
@ pg_init ( Slice u ) p i pid i type → v {
    : ~ i k 0
    ~ < k PAGE_SIZE {
        ( slice_put_u64_le p k 0 )
        = k + k 8
    }
    ( slice_put_u32_le p PG_ID pid )
    ( slice_put_u16_le p PG_TYPE type )
}

// The page's checksum: CRC-32 of its bytes with the crc field read as
// zero (it is the bytes before the field, four zero bytes, the bytes
// after it).
@ pg_checksum ( Slice u ) p → i {
    : i c0 ( crc32_update_slice 0 ( slice_prefix [u] p PG_CRC ) )
    : ( Vec u ) zero ( vec_zeroed [u] 4 )
    : i c1 ( crc32_update_slice c0 ( slice_from_vec [u] zero ) )
    ^ ( crc32_update_slice c1 ( slice_window [u] p + PG_CRC 4 - PAGE_SIZE + PG_CRC 4 ) )
}

@ pg_crc ( Slice u ) p → i { ^ ( slice_u32_le p PG_CRC ) }

@ pg_set_crc ( Slice u ) p i c → v { ( slice_put_u32_le p PG_CRC c ) }

// Whether a page read from disk is intact: an all-zero page (a hole the
// file was extended over) is a page never written, and passes; anything
// else must carry its own number and a matching checksum.
@ pg_verify ( Slice u ) p i pid → b {
    ? & == ( pg_crc p ) 0 == ( pg_lsn p ) 0 {
        : ~ i k 0
        ~ < k PAGE_SIZE {
            ? != ( slice_u64_le p k ) 0 { ^ F } {}
            = k + k 8
        }
        ^ T
    } {}
    ? != ( pg_id p ) pid { ^ F } {}
    ^ == ( pg_crc p ) ( pg_checksum p )
}
