// field_of_a_loop_element_handed_to_a_sink_while_a_view_of_it_lives: agora #587 — `~ x t { ( gone . x name ) }` with a view of that field of t's element taken before and read after
// Closed: a field of a `~` loop's element handed to a parameter that takes it ends the borrows of the container's elements, in the function and at its callers (agora #587).
// main 005f953: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #587: `~ x t { ( gone . x name ) }` with a view of that field of t's element taken before and read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ gone sink String a → v {}

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element whose field is handed to a sink` ) 1 } )
    : s v ( string_data . ( vec_at [P] t 0 ) name )
    ~ x t { ( gone . x name ) }
    ( nurl_println v )
    ^ 0
}
