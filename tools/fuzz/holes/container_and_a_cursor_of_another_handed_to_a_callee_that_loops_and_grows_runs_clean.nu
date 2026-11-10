// container_and_a_cursor_of_another_handed_to_a_callee_that_loops_and_grows_runs_clean: agora #589 — `( walk t cur )` with cur a cursor of ANOTHER Vec, and `( walk t u )`
// Control for agora #589: two different containers, or a cursor of another one, share nothing.
// map: §2.4 | A2 | runs-clean | - | agora #589: `( walk t cur )` with cur a cursor of ANOTHER Vec, and `( walk t u )`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ walk ( Vec String ) xs ( Vec String ) ys → v {
    : ~ i done 0
    ~ x xs {
        ( nurl_println ( string_data x ) )
        ? == done 0 { ( grow ys ) = done 1 } {}
    }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ( Vec String ) u ( vec_new [String] )
    ( vec_push [String] u ( string_from `another container, long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur u
    ( walk t cur )
    ( walk t u )
    ^ 0
}
