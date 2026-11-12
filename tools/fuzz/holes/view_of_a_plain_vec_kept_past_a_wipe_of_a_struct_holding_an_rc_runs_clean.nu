// view_of_a_plain_vec_kept_past_a_wipe_of_a_struct_holding_an_rc_runs_clean: a slice of a Vec that is no Rc's payload kept past a helper clearing a struct's Rc payload (the shape the fix must keep)
// Closed: the rule compares what a call may change through an argument with what a view's source is or holds in its own storage (agora #712).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #712: a view of a plain Vec kept past a wipe of a struct holding an Rc
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Ctx { ( Rc ( Vec ( Vec u ) ) ) log i n }

@ wipe Ctx c → v { ( vec_clear [( Vec u )] ( rc_get [( Vec ( Vec u ) )] . c log ) ) }

@ main → i {
    : ( Vec ( Vec u ) ) v0 ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] v0 ( vec_new [u] ) )
    : Ctx c @ Ctx { ( rc_new [( Vec ( Vec u ) )] v0 ) 1 }
    : ( Vec u ) plain ( vec_new [u] )
    ( vec_push [u] plain 7 )
    : ( Slice u ) sl ( slice_from_vec [u] plain )
    ( wipe c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
