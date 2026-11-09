// loop_element_grown_through_another_borrow_runs_clean: agora #482 — `~ x b` over `b = ( vec_at vv 0 )`; the element `x` is grown through `b2`, another `vec_at` of the row, before a view of `x` is taken
// The shape the fix must keep: an element's own growth leaves its handle as it is (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop element grown through another borrow of its row
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) b ( vec_at [( Vec String )] vv 0 )
    : ( Vec String ) b2 ( vec_at [( Vec String )] vv 0 )
    ~ x b {
        ( string_push_str ( vec_at [String] b2 0 ) `, and a much longer tail that forces the buffer to move elsewhere` )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
