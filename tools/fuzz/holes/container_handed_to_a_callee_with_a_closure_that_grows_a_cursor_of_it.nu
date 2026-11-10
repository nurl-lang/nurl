// container_handed_to_a_callee_with_a_closure_that_grows_a_cursor_of_it: agora #589 — `( walk t \ → v { ( grow cur ) } )`: the callee loops over t and runs the closure
// Closed: a borrow that is a copy of an owner's handle is that owner's own storage where a callee may move it (bck_sx_mut_storage), so the argument-alias and closure-reach checks see the owner (agora #589).
// main 9e7c031: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #589: `( walk t \ → v { ( grow cur ) } )`: the callee loops over t and runs the closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ walk ( Vec String ) xs ( @ v ) f → v {
    : ~ i done 0
    ~ x xs {
        ( nurl_println ( string_data x ) )
        ? == done 0 { ( f ) = done 1 } {}
    }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i done 0
    ( walk t \ → v { ( grow cur ) } )
    ^ 0
}
