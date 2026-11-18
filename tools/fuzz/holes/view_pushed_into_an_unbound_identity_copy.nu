// view_pushed_into_an_unbound_identity_copy: a view pushed into `( id vs )`, an unbound call as the container, read after its source's block
// Closed (agora #395): the store lands in the owner an unbound call container lends or an option payload cursor reads (__bck_store_roots, __cursor_src_of), as through a bound borrow (agora #292).
// main 6005efcb: refused.
// map: §2.13 | A2 | rejected | - | agora #395: a view pushed into `( id vs )`, an unbound call as the container, read after its source's block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ( Vec s ) x → ( Vec s ) { ^ x }

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    {
        : String loc ( string_from `a heap string freed at the end of this block, long enough for the heap` )
        ( vec_push [s] ( id vs ) ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
