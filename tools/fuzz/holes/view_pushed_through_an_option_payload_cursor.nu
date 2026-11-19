// view_pushed_through_an_option_payload_cursor: a view pushed through `?? ov { T w → ( vec_push w … ) }`, an option payload cursor, read after its source's block
// Closed (agora #395): the store lands in the owner an unbound call container lends or an option payload cursor reads (__bck_store_roots, __cursor_src_of), as through a bound borrow (agora #292).
// main 6005efcb: refused.
// map: §2.13 | A2 | rejected | - | agora #395: a view pushed through `?? ov { T w → ( vec_push w … ) }`, an option payload cursor, read after its source's block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ?( Vec s ) ov @ ?( Vec s ) { T ( vec_new [s] ) }
    {
        : String loc ( string_from `a heap string freed at the end of this block, long enough for the heap` )
        ?? ov { T w → ( vec_push [s] w ( string_data loc ) ) F → {} }
    }
    ?? ov { T w → ( nurl_println ( vec_at [s] w 0 ) ) F → {} }
    ^ 0
}
