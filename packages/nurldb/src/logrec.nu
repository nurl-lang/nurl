// packages/nurldb/src/logrec.nu — what the log records say.
//
// Every record starts with its kind (one byte). Integers are little-endian.
//
//   R_PAGE_INIT    u32 pid  u16 type              a page formatted
//   R_HEAP_INSERT  u32 pid  u16 slot  u32 n  n bytes   a tuple placed
//   R_HEAP_SETX    u32 pid  u16 slot  u64 xmax  u32 cmax  u64 next
//                                                  a version deleted /
//                                                  superseded (or undone)
//   R_LINK         u32 pid  u32 next              a page chain extended
//   R_PAGE_IMAGE   u32 pid  PAGE_SIZE bytes       a page replaced whole
//                                                  (a B+tree split, a prune)
//   R_COMMIT       u64 xid
//   R_ABORT        u64 xid
//   R_CHECKPOINT   u64 next_xid  u64 npages       every page before it is
//                                                  on disk
//   R_META         u32 key  u64 value             a database-wide counter
//   R_BT_INSERT    u32 pid  u16 pos  u32 child  u16 n  n bytes
//                                                  an index entry put in
//   R_BT_DELETE    u32 pid  u16 pos               an index entry taken out
//
// Redo (recovery.nu) applies a page record only to a page whose LSN is
// below the record's: a change the page already holds is skipped, so
// replaying the log twice changes nothing the first replay did not.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: i R_PAGE_INIT 1
: i R_HEAP_INSERT 2
: i R_HEAP_SETX 3
: i R_LINK 4
: i R_PAGE_IMAGE 5
: i R_COMMIT 6
: i R_ABORT 7
: i R_CHECKPOINT 8
: i R_META 9
: i R_BT_INSERT 10
: i R_BT_DELETE 11

@ rec_new i kind i cap → ( Vec u ) {
    : ( Vec u ) r ( vec_with_cap [u] cap )
    ( vec_push [u] r # u kind )
    ^ r
}

@ rec_u16 ( Vec u ) r i x → v { ( vec_push_word_u8 r x 2 F ) }

@ rec_u32 ( Vec u ) r i x → v { ( vec_push_word_u8 r x 4 F ) }

@ rec_u64 ( Vec u ) r i x → v { ( vec_push_word_u8 r x 8 F ) }

@ rec_bytes ( Vec u ) r ( Slice u ) b → v {
    : i at ( vec_len [u] r )
    : i n ( slice_len [u] b )
    : b _g ( vec_resize_zeroed [u] r + at n )
    ( slice_copy [u] ( slice_window [u] ( slice_from_vec [u] r ) at n ) b )
}

@ rec_kind ( Slice u ) r → i { ^ ( slice_byte r 0 ) }

@ rec_pid ( Slice u ) r → i { ^ ( slice_u32_le r 1 ) }
