// loop_goes_on_after_its_container_grew_through_a_join_of_a_cursor_bound_to_a_name: agora #599 — `: c ? k cur other`, then `~ x t { ( grow c ) }`: c is cur at run time
// Closed: a binding of a join or a value block whose arms are all names, each an owner or a copy of an owner's handle, is a copy of the handle of whichever arm ran (`hc_`) (agora #599).
// main 4e09040: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #599: `: c ? k cur other`, then `~ x t { ( grow c ) }`: c is cur at run time
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
    : ~ ( Vec String ) cur t
    : ~ i done 0
    : ( Vec String ) other ( vec_new [String] )
    : ( Vec String ) c ? == done 0 cur other
    ~ x t {
        ( nurl_println ( string_data x ) )
        ? == done 0 { ( grow c ) = done 1 } {}
    }
    ^ 0
}
