// loop_element_grown_through_itself_then_read_runs_clean: agora #482 — `~ x t` over an owned `t`; `x` grown through itself, then read
// The shape the fix must keep: a change through the element is no end of it (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop element grown through itself, then read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ~ x t {
        ( string_push_str x `, and a much longer tail that forces the buffer to move elsewhere` )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
