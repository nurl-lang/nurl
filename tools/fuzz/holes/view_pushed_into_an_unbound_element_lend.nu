// view_pushed_into_an_unbound_element_lend: a view pushed into `( vec_at vv 0 )`, an unbound call as the container, read after its source's block
// Closed (agora #395): the store lands in the owner an unbound call container lends or an option payload cursor reads (__bck_store_roots, __cursor_src_of), as through a bound borrow (agora #292).
// main 6005efcb: refused.
// map: §2.13 | A2 | rejected | - | agora #395: a view pushed into `( vec_at vv 0 )`, an unbound call as the container, read after its source's block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    {
        : String loc ( string_from `a heap string freed at the end of this block, long enough for the heap` )
        ( vec_push [s] ( vec_at [( Vec s )] vv 0 ) ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
