// loop_goes_on_after_a_helper_grew_its_container_through_a_cursor: agora #493 — `~ x t { ( grow cur ) }`, grow pushing into its parameter: the loop reads its next element from t's old buffer
// Closed: a `~` loop holds a view of the storage it reads its elements from — its cursor — ended as any view of it is; a path that goes on to the next element after it ended is refused (agora #493).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #493: `~ x t { ( grow cur ) }`, grow pushing into its parameter: the loop reads its next element from t's old buffer
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
    : ~ ( Vec String ) cur t
    : ~ i done 0
    ~ x t {
        ( nurl_println ( string_data x ) )
        ? == done 0 { ( grow cur ) = done 1 } {}
    }
    ^ 0
}
