// field_of_a_loop_element_handed_to_a_generic_sink_while_a_borrow_of_it_lives: agora #587 — `: String e . ( vec_at [P] t 0 ) name`, `~ x t { ( gone [String] . x name ) }`, then e read
// Closed: a field of a `~` loop's element handed to a parameter that takes it ends the borrows of the container's elements, in the function and at its callers (agora #587).
// main 005f953: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #587: `: String e . ( vec_at [P] t 0 ) name`, `~ x t { ( gone [String] . x name ) }`, then e read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ gone [A] sink A a → v {}

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element whose field is handed to a sink` ) 1 } )
    : String e . ( vec_at [P] t 0 ) name
    ~ x t { ( gone [String] . x name ) }
    ( nurl_println ( string_data e ) )
    ^ 0
}
