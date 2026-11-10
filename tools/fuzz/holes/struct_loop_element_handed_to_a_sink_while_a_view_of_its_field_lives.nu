// struct_loop_element_handed_to_a_sink_while_a_view_of_its_field_lives: agora #490 — `~ x t { ( eat x ) }`, eat taking a `sink P`, with a view of the element's String field taken before and read after
// Closed: a `~` loop's element moved out is an element of its container gone: the borrows of that container's elements end, as at `vec_remove` (agora #490).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #490: `~ x t { ( eat x ) }`, eat taking a `sink P`, with a view of the element's String field taken before and read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ eat sink P p → v {}

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element handed to a sink, a view of its field` ) 1 } )
    : s v ( string_data . ( vec_at [P] t 0 ) name )
    ~ x t { ( eat x ) }
    ( nurl_println v )
    ^ 0
}
