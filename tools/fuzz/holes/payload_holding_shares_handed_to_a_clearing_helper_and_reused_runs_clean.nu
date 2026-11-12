// payload_holding_shares_handed_to_a_clearing_helper_and_reused_runs_clean: `: ( Vec ( Rc String ) ) p ( rc_get r )` handed to a helper that clears it, then pushed to and read: a borrow reaches its shares through what it borrows from (the shape the fix must keep)
// Closed: the rule compares what a call may change through an argument with what a view's source is or holds in its own storage (agora #712).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #712: a payload of shares cleared by a helper and reused
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Vec ( Rc String ) ) p → v { ( vec_clear [( Rc String )] p ) }

@ main → i {
    : ( Vec ( Rc String ) ) v ( vec_new [( Rc String )] )
    ( vec_push [( Rc String )] v ( rc_new [String] ( string_from `an element string long enough for a heap buffer` ) ) )
    : ( Rc ( Vec ( Rc String ) ) ) r ( rc_new [( Vec ( Rc String ) )] v )
    : ( Vec ( Rc String ) ) p ( rc_get [( Vec ( Rc String ) )] r )
    ( wipe p )
    ( vec_push [( Rc String )] p ( rc_new [String] ( string_from `another element string long enough for a heap buffer` ) ) )
    ( nurl_println_int ( vec_len [( Rc String )] p ) )
    ^ 0
}
