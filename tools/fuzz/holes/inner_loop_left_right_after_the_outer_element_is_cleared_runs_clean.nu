// inner_loop_left_right_after_the_outer_element_is_cleared_runs_clean: agora #482 — `~ r vv { : ~ cur r ~ x r { … } }`: the inner element read before the outer element is cleared through a cursor, and the inner loop left right after
// The shape the fix must keep: a change made through the loop element itself, or through a borrow of it or of its field, drops its own elements, not the element (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: an inner loop left right after the outer element is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    ~ r vv {
        : ~ ( Vec String ) cur r
        ~ x r {
            ( nurl_println ( string_data x ) )
            ( vec_clear [String] cur )
            break
        }
    }
    ^ 0
}
