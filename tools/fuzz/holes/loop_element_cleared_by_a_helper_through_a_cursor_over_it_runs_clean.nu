// loop_element_cleared_by_a_helper_through_a_cursor_over_it_runs_clean: agora #482 — `~ r vv { : ~ cur r ( wipe cur ) }`: each row cleared by a helper through a cursor over it; the loop goes on
// The shape the fix must keep: a change made through the loop element itself, or through a borrow of it or of its field, drops its own elements, not the element (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop element cleared by a helper through a cursor over it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ wipe ( Vec String ) v → v { ( vec_clear [String] v ) }

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ~ ( Vec String ) t2 ( vec_new [String] )
    ( vec_push [String] t2 ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] vv t2 )
    ~ r vv {
        : ~ ( Vec String ) cur r
        ( wipe cur )
    }
    ^ 0
}
