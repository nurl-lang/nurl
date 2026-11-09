// field_of_an_inner_block_owner_moved_outward_runs_clean: agora #533 guard — `{ : ~ E x ( mk … )  = w . x kids }`: an owned struct of the inner block hands its field over, and `w` is read after the block.
// Guard: an owner's field moves out; the binding owns it, borrows nothing, and outlives the block.
// main: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #533 guard: a field of an inner block's owned struct moved to an outer binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { ( Vec E ) kids String name }

@ mk String s → E { ^ @ E { ( vec_new [E] ) s } }

@ main → i {
    : ( Vec E ) top ( vec_new [E] )
    ( vec_push [E] top ( mk ( string_from `a parent name long enough for the heap` ) ) )
    : ~ ( Vec E ) w ( vec_new [E] )
    {
        : ~ E x ( mk ( string_from `an owned local` ) )
        ( vec_push [E] . x kids ( mk ( string_from `a child name long enough for the heap` ) ) )
        = w . x kids
    }
    ( vec_clear [E] top )
    ( nurl_println_int # i ( vec_len [E] w ) )
    ^ 0
}
