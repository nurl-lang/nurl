// callee_handing_a_field_of_its_parameters_loop_elements_to_a_sink_while_the_caller_views_one: agora #587 — `@ strip ( Vec P ) t → v { ~ x t { ( gone . x name ) } }` called with a view of an element's name read after
// Closed: a field of a `~` loop's element handed to a parameter that takes it ends the borrows of the container's elements, in the function and at its callers (agora #587).
// main 005f953: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #587: `@ strip ( Vec P ) t → v { ~ x t { ( gone . x name ) } }` called with a view of an element's name read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: Q { P inner i k }

@ gone sink String a → v {}

@ strip ( Vec P ) t → v { ~ x t { ( gone . x name ) } }

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element whose field is handed to a sink` ) 1 } )
    ( vec_push [P] t @ P { ( string_from `a second struct element, long enough for the heap` ) 2 } )
    : s v ( string_data . ( vec_at [P] t 1 ) name )
    ( strip t )
    ( nurl_println v )
    ^ 0
}
