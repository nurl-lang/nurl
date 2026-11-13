// cursor_of_a_binding_moved_into_a_block_local_struct_read_after_the_block_stays_refused: `: ~ cur t`, `{ : ~ H q @ H { t 0 } … }`, then `cur` read after the block
// Kept: a borrow of a value moved into a struct's field — moved onto the field path, `bxf_` — ends with the struct, also where the struct's scope ends (bck_root_end; agora #799's review: the field path's borrows were ended for views only there).
// main 83059aae: refused.
// map: §2.10 | A2 | rejected | - | agora #799: a cursor of a value moved into a block-local struct, read after the block
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: H { ( Vec i ) items i n }
: HS { String s i n }

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    {
        : ~ H q @ H { t 0 }
        ( nurl_println_int . q n )
    }
    ( nurl_println_int ( vec_len [i] cur ) )
    ^ 0
}
