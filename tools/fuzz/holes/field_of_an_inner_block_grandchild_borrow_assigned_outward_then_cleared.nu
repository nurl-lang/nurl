// field_of_an_inner_block_grandchild_borrow_assigned_outward_then_cleared: `{ : E x ( vec_at [E] . b0 kids 0 )  = w . x kids }`, then the parent's kids cleared through a field viewer `: ~ ( Vec E ) w2 . b0 kids`.
// Closed: a field read out of a struct of an inner scope "moves out" with that struct's drop flag (mem_udrop_field_move); where the struct is itself a borrow (`vec_at`) the binding owns nothing on that path, and its borrow row (mode `t`, bck_note_moved_field) now begins from the field there, flattened to what the struct borrows (agora #533). It was marked as owning, so the block's end retired its only tie.
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #533: a field of an inner block's element of an element assigned outward, cleared through a field viewer
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: E { ( Vec E ) kids String name }

@ mk String s → E { ^ @ E { ( vec_new [E] ) s } }

@ main → i {
    : ~ E b0 ( mk ( string_from `root` ) )
    : ~ E p ( mk ( string_from `parent` ) )
    ( vec_push [E] . p kids ( mk ( string_from `a grandchild name long enough for the heap` ) ) )
    ( vec_push [E] . b0 kids p )
    : ~ ( Vec E ) w ( vec_new [E] )
    {
        : E x ( vec_at [E] . b0 kids 0 )
        = w . x kids
    }
    : ~ ( Vec E ) w2 . b0 kids
    ( vec_clear [E] w2 )
    ( nurl_println_int # i ( vec_len [E] w ) )
    ^ 0
}
