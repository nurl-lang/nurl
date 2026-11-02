// view_pushed_through_an_identity_copy_of_an_element_outlives_its_source: agora #414 — `: ( Vec s ) w ( id ( vec_at [( Vec s )] vv 0 ) )`, then the push into `w`; read through `vv`
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: heap-use-after-free (base 22fd0184 too).
// map: PushArg | A1 | rejected | - | agora #414: a view pushed through an identity copy of an element, read through the outer Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ( Vec s ) x → ( Vec s ) { ^ x }

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        : ( Vec s ) w ( id ( vec_at [( Vec s )] vv 0 ) )
        ( vec_push [s] w ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}
