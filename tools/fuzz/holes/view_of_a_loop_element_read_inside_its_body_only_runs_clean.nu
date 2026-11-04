// view_of_a_loop_element_read_inside_its_body_only_runs_clean: agora #471 — a view of `x` taken and read inside `~ x t` only; `t` ends after the loop (the shape the fix must keep)
// Closed: nothing outlives the container: the view ends with the body, before `t` does (agora #471).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a view of a loop element read inside the loop body only
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string read inside the loop body only` ) )
        ~ x t {
            : s v ( string_data x )
            ( nurl_println v )
            ( nurl_println ( string_data x ) )
        }
    }
    ^ 0
}
