// view_pushed_into_an_unbound_box_payload: a view pushed into `( box_get bx )`, an unbound call as the container, read after its source's block
// Closed (agora #395): the store lands in the owner an unbound call container lends or an option payload cursor reads (__bck_store_roots, __cursor_src_of), as through a bound borrow (agora #292).
// main 6005efcb: refused.
// map: §2.13 | A2 | rejected | - | agora #395: a view pushed into `( box_get bx )`, an unbound call as the container, read after its source's block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ main → i {
    : ( Box ( Vec s ) ) bx ( box_new [( Vec s )] ( vec_new [s] ) )
    {
        : String loc ( string_from `a heap string freed at the end of this block, long enough for the heap` )
        ( vec_push [s] ( box_get [( Vec s )] bx ) ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] ( box_get [( Vec s )] bx ) 0 ) )
    ^ 0
}
