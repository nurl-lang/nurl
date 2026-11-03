// view_pushed_through_a_join_of_names_read_inside_its_block: agora #414 — the view pushed through `: ( Vec s ) w ? == c 1 { vs } { vs2 }` read while its source is still in scope (the shape the fix must keep)
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #414: a view pushed through a binding of a join of names, read before its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    : ( Vec s ) vs2 ( vec_new [s] )
    : i c 1
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        : ( Vec s ) w ? == c 1 { vs } { vs2 }
        ( vec_push [s] w ( string_data loc ) )
        ( nurl_println ( vec_at [s] vs 0 ) )
    }
    ^ 0
}
