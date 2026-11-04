// view_of_a_loop_elements_own_storage_read_while_its_container_lives_runs_clean: agora #471 — views of `~` loop elements' own storage kept in an outer `( Vec s )`, read inside the loop and after it while the container lives, the container grown in between (the shape the fix must keep)
// Closed: a view of a loop element's own storage is reached through an element of the container (`^t`), which the container growing leaves where it is — a String's buffer does not move when the Vec grows (agora #471).
// main 0c11a93: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: views of `~` loop elements' own storage read while the container lives, after it grew
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a first string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    : ( Vec s ) ws ( vec_new [s] )
    ~ x t {
        ( vec_push [s] ws ( string_data x ) )
        ( nurl_println ( string_data x ) )
    }
    ( vec_push [String] t ( string_from `a third string, which may move the Vec's buffer` ) )
    ( vec_push [String] t ( string_from `a fourth string, which may move it again` ) )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ( nurl_println ( vec_at [s] ws 1 ) )
    ^ 0
}
