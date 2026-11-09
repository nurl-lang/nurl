// generic_clearing_through_its_closure_with_the_view_read_before_runs_clean: agora #461 — `b_g05_task`'s generic with the clearing closure, the view read only before the call
// The shape the fix must keep: a view read before the call (agora #461).
// main 21a0fb5: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #461: a generic clearing through its closure, the view read before
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ each0 [T] ( Vec T ) vv ( @ v T ) f → v {
    ( f ( vec_at [T] vv 0 ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) w ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] w ( vec_new [String] ) )
    : ( Vec String ) r ( vec_at [( Vec String )] w 0 )
    ( vec_push [String] r ( string_from `a string long enough to live on the heap for sure` ) )
    : s d ( string_data ( vec_at [String] r 0 ) )
    ( nurl_println d )
    ( each0 [( Vec String )] w \ ( Vec String ) z → v { ( vec_clear [String] z ) } )
    ( nurl_println_int # i ( vec_len [( Vec String )] w ) )
    ^ 0
}
