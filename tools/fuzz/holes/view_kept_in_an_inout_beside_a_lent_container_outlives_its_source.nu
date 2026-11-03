// view_kept_in_an_inout_beside_a_lent_container_outlives_its_source: agora #414 — `( put2 ( vec_at [( Vec s )] vv 0 ) out ( string_data loc ) )`, `put2` keeping its third argument in its `inout` second; `out` read after the block (the store must still land in the `inout` argument when the first is a lent value)
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: rejected (a guard: the container a lent first argument names does not take the store from the `inout` one).
// map: PushArg | A1 | rejected | - | agora #414: a view kept in an inout argument beside a lent first argument, read through the inout one
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ put2 ( Vec s ) a inout ( Vec s ) b s x → v { ( vec_push [s] b x ) }

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    : ~ ( Vec s ) out ( vec_new [s] )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ( put2 ( vec_at [( Vec s )] vv 0 ) out ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] out 0 ) )
    ^ 0
}
