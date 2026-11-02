// view_pushed_through_a_join_of_fields_outlives_its_source: agora #414 — `: ( Vec s ) w ? == c 1 . o items . o2 items`, then the push into `w`; read through `. o items`
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed through a binding of a join of fields, read through a struct
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { ( Vec s ) items i n }

@ main → i {
    : S o @ S { ( vec_new [s] ) 1 }
    : S o2 @ S { ( vec_new [s] ) 1 }
    : i c 1
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        : ( Vec s ) w ? == c 1 . o items . o2 items
        ( vec_push [s] w ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] . o items 0 ) )
    ^ 0
}
