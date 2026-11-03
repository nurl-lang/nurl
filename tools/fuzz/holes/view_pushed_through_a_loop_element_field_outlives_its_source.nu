// view_pushed_through_a_loop_element_field_outlives_its_source: agora #414 — `~ e vst { ( vec_push [s] . e items ( string_data loc ) ) }`, `vst` a Vec of structs with a `( Vec s )` field
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed into a field of a `~` loop's element, read through the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { ( Vec s ) items i n }

@ main → i {
    : ( Vec S ) vst ( vec_new [S] )
    ( vec_push [S] vst @ S { ( vec_new [s] ) 1 } )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ~ e vst { ( vec_push [s] . e items ( string_data loc ) ) }
    }
    ( nurl_println ( vec_at [s] . ( vec_at [S] vst 0 ) items 0 ) )
    ^ 0
}
