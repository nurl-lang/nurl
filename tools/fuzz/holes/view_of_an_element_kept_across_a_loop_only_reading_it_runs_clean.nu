// view_of_an_element_kept_across_a_loop_only_reading_it_runs_clean: agora #350 — a view of `t`'s element kept across `~ x t` that only reads `x` and pushes copies into another Vec (the shape the fix must keep)
// Closed: nothing is changed through the element: the view stays (agora #350, #471).
// main 0c11a93: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #350: a view of an element kept across a loop that only reads its elements
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string that is only read by the loop` ) )
    : ( Vec String ) u ( vec_new [String] )
    : s v ( string_data ( vec_at [String] t 0 ) )
    ~ x t {
        ( vec_push [String] u ( string_from ( string_data x ) ) )
        ( nurl_println ( string_data x ) )
    }
    ( nurl_println v )
    ^ 0
}
