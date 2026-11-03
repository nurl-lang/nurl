// view_pushed_through_a_nested_loop_element_outlives_its_source: agora #414 — as …_loop_element, two loops deep: `~ row vvv { ~ e row { … } }`
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed through the element of a `~` loop over another loop's element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec ( Vec s ) ) ) vvv ( vec_new [( Vec ( Vec s ) )] )
    ( vec_push [( Vec ( Vec s ) )] vvv ( vec_new [( Vec s )] ) )
    ( vec_push [( Vec s )] ( vec_at [( Vec ( Vec s ) )] vvv 0 ) ( vec_new [s] ) )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ~ row vvv { ~ e row { ( vec_push [s] e ( string_data loc ) ) } }
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] ( vec_at [( Vec ( Vec s ) )] vvv 0 ) 0 ) 0 ) )
    ^ 0
}
