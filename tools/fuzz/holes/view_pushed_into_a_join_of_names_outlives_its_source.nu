// view_pushed_into_a_join_of_names_outlives_its_source: agora #414 — the join itself the push's container: `( vec_push [s] ? == c 1 { vs } { vs2 } ( string_data loc ) )`
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed into a join of names as the container, read through an owner
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    : ( Vec s ) vs2 ( vec_new [s] )
    : i c 1
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ( vec_push [s] ? == c 1 { vs } { vs2 } ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
