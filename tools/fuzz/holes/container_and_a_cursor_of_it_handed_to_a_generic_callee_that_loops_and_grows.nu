// container_and_a_cursor_of_it_handed_to_a_generic_callee_that_loops_and_grows: agora #589 — the same through a generic `@ walkg [A] ( Vec A ) v ( Vec A ) w A a`
// Closed: a borrow that is a copy of an owner's handle is that owner's own storage where a callee may move it (bck_sx_mut_storage), so the argument-alias and closure-reach checks see the owner (agora #589).
// main 9e7c031: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #589: the same through a generic `@ walkg [A] ( Vec A ) v ( Vec A ) w A a`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ walkg [A] ( Vec A ) v ( Vec A ) w A a → i {
    : ~ i n 0
    : ~ i sum 0
    ~ x v {
        ~ < n 64 { ( vec_push [A] w a ) = n + n 1 }
        ( vec_push [A] w x )
        = sum + sum 1
    }
    ^ sum
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i done 0
    : ( Vec i ) u ( vec_new [i] )
    ( vec_push [i] u 1 ) ( vec_push [i] u 2 ) ( vec_push [i] u 3 )
    : ~ ( Vec i ) uc u
    ( nurl_println_int ( walkg [i] u uc 7 ) )
    ^ 0
}
