// cursor_of_a_binding_assigned_into_a_block_local_field_read_after_the_block_stays_refused: `: ~ cur t`, `{ : ~ H q … = . q items t … }`, then `cur` read after the block
// Kept: a borrow of a value assigned into a struct's field ends with the struct, also where the struct's scope ends (agora #799's review).
// main 83059aae: refused.
// map: §2.10 | A2 | rejected | - | agora #799: a cursor of a value assigned into a block-local field, read after the block
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }
: W { H h }

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    {
        : ~ H q @ H { ( vec_new [i] ) 0 }
        = . q items t
        ( nurl_println_int . q n )
    }
    ( nurl_println_int ( vec_len [i] cur ) )
    ^ 0
}
