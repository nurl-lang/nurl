// view_pushed_through_a_loop_element_read_inside_its_block: agora #414 — the view pushed through a `~` loop's element read while its source is still in scope (the shape the fix must keep)
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #414: a view pushed through a `~` loop's element, read before its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ~ e vv { ( vec_push [s] e ( string_data loc ) ) }
        ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    }
    ^ 0
}
