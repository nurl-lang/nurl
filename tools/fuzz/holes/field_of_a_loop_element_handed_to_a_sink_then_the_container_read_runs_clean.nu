// field_of_a_loop_element_handed_to_a_sink_then_the_container_read_runs_clean: agora #587 — after `~ x t { ( gone . x name ) }` the elements read back with an empty name and their other fields
// Closed: the field (or the element) is emptied in the element's slot, found through the Vec's control block where the buffer is at that moment (agora #587).
// main 005f953: AddressSanitizer: heap-use-after-free (the container released it again, or the old buffer was written).
// map: §2.5 | A2 | runs-clean | - | agora #587: after `~ x t { ( gone . x name ) }` the elements read back with an empty name and their other fields
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: Q { P inner i k }

@ gone sink String a → v {}

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element whose field is handed to a sink` ) 1 } )
    ( vec_push [P] t @ P { ( string_from `a second struct element, long enough for the heap` ) 2 } )
    ~ x t { ( gone . x name ) }
    ( nurl_println_int ( string_len . ( vec_at [P] t 0 ) name ) )
    ( nurl_println_int . ( vec_at [P] t 1 ) n )
    ^ 0
}
