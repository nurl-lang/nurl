// loop_goes_on_after_its_container_grew_through_a_cursor_a_helper_handed_back_whole: agora #493 — `~ x t { ( grow ( pickv cur other ) ) }`, pickv handing its first argument back: the buffer moved is t's own
// Closed: a value a callee hands back whole out of a handle copy is that copy, not a part of it; the loop's cursor ends (agora #493, a regression of github#1710's `deep` exemption on main 005f953..6d1229f).
// main 6d1229f: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #493: `~ x t { ( grow ( pickv cur other ) ) }`, pickv handing its first argument back: the buffer moved is t's own
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ pickv ( Vec String ) a ( Vec String ) b → ( Vec String ) { ^ a }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i done 0
    : ( Vec String ) other ( vec_new [String] )
    ~ x t {
        ( nurl_println ( string_data x ) )
        ? == done 0 { ( grow ( pickv cur other ) ) = done 1 } {}
    }
    ^ 0
}
