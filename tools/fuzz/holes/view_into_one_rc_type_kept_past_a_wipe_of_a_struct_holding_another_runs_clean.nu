// view_into_one_rc_type_kept_past_a_wipe_of_a_struct_holding_another_runs_clean: a slice through `( Rc ( Vec u ) )` kept past wiping a struct that holds an `( Rc ( Vec String ) )`: Rcs of other types are other values (the shape the fix must keep)
// Closed: the rule compares what a call may change through an argument with what a view's source is or holds in its own storage (agora #712).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #712: a view into one Rc type kept past a wipe of a struct holding another
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Ctx { ( Rc ( Vec String ) ) log i n }

@ wipe Ctx c → v { ( vec_clear [String] ( rc_get [( Vec String )] . c log ) ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : Ctx c @ Ctx { ( rc_new [( Vec String )] v ) 1 }
    : ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] w )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( wipe c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
