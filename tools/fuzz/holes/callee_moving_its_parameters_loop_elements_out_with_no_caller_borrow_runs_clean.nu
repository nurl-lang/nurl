// callee_moving_its_parameters_loop_elements_out_with_no_caller_borrow_runs_clean: agora #588 — `( wipe t )` with no borrow of t's elements live, t used after
// Control for agora #588: the callee is refused nowhere; only a borrow of the argument's elements read after the call is.
// map: §2.5 | A2 | runs-clean | - | agora #588: `( wipe t )` with no borrow of t's elements live, t used after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wipe ( Vec String ) t → v { ~ x t { ( string_free x ) } }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `second string long enough for a heap buffer here` ) )
    : s v ( string_data ( vec_at [String] t 1 ) )
    ( nurl_println v )
    ( wipe t )
    ( nurl_println_int ( vec_len [String] t ) )
    ^ 0
}
