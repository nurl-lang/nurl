// loop_element_freed_while_a_view_of_the_containers_element_lives: agora #490 — `: s v ( string_data ( vec_at t 0 ) )`, then `~ x t { ( string_free x ) }`, then v is read
// Closed: a `~` loop's element moved out is an element of its container gone: the borrows of that container's elements end, as at `vec_remove` (agora #490).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #490: `: s v ( string_data ( vec_at t 0 ) )`, then `~ x t { ( string_free x ) }`, then v is read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string handed to string_free through its loop element` ) )
    : s v ( string_data ( vec_at [String] t 0 ) )
    ~ x t { ( string_free x ) }
    ( nurl_println v )
    ^ 0
}
