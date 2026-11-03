// view_kept_in_an_inout_beside_a_lent_container_leaves_that_container_alone: agora #414 — as view_kept_in_an_inout_beside_a_lent_container_outlives_its_source, `out` read inside the block and `vv` after it: `put2` changes nothing its first argument holds (the shape the fix must keep)
// Closed: a value kept in a container whose handle is a copy of an owner's, or a part of one, without being its borrow — a binding of a `?` / `??` join of names, a `~` loop's element, a `??` payload read in place, a value a call lends (`( id ( vec_at vv 0 ) )`), or such a value handed to the call as the container itself — lands in that owner too, which holds the view (`hr_`, __bck_store_owners; agora #414).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #414: a view kept in an inout argument beside a lent first argument, the lent one read after the view's source ends
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
        ( nurl_println ( vec_at [s] out 0 ) )
    }
    ( nurl_println_int ( vec_len [s] ( vec_at [( Vec s )] vv 0 ) ) )
    ^ 0
}
