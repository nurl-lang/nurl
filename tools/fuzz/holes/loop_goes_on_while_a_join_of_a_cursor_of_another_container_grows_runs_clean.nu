// loop_goes_on_while_a_join_of_a_cursor_of_another_container_grows_runs_clean: agora #599 — `: c ? k cur other` with cur a cursor of ANOTHER Vec, grown inside `~ x t`
// Control for agora #599: a join of cursors of ANOTHER container shares nothing with the one the loop walks.
// map: §2.5 | A2 | runs-clean | - | agora #599: `: c ? k cur other` with cur a cursor of ANOTHER Vec, grown inside `~ x t`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ( Vec String ) u ( vec_new [String] )
    ( vec_push [String] u ( string_from `another container, long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur u
    : ~ i done 0
    : ( Vec String ) other ( vec_new [String] )
    : ( Vec String ) c ? == done 0 cur other
    ~ x t {
        ( nurl_println ( string_data x ) )
        ? == done 0 { ( grow c ) = done 1 } {}
    }
    ^ 0
}
