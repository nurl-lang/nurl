// loop_inside_a_closure_over_a_capture_grown_through_a_captured_cursor_of_it: agora #589 — a closure whose body loops over captured t and grows captured cur, a cursor of t
// Closed: a borrow that is a copy of an owner's handle is that owner's own storage where a callee may move it (bck_sx_mut_storage), so the argument-alias and closure-reach checks see the owner (agora #589).
// main 9e7c031: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #589: a closure whose body loops over captured t and grows captured cur, a cursor of t
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ growlen ( Vec String ) v → i { ( grow v ) ^ ( vec_len [String] v ) }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i done 0
    : ( @ v ) f \ → v {
        : ~ i d 0
        ~ x t {
            ( nurl_println ( string_data x ) )
            ? == d 0 { ( grow cur ) = d 1 } {}
        }
    }
    ( f )
    ^ 0
}
