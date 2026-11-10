// nested_field_of_a_loop_element_handed_to_a_sink_runs_clean: agora #587 — `~ x t { ( gone . . x inner name ) }`: a field of a field of the element, emptied in its slot
// Closed: the field (or the element) is emptied in the element's slot, found through the Vec's control block where the buffer is at that moment (agora #587).
// main 005f953: AddressSanitizer: heap-use-after-free (the container released it again, or the old buffer was written).
// map: §2.5 | A2 | runs-clean | - | agora #587: `~ x t { ( gone . . x inner name ) }`: a field of a field of the element, emptied in its slot
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: Q { P inner i k }

@ gone sink String a → v {}

@ main → i {
    : ( Vec Q ) t ( vec_new [Q] )
    ( vec_push [Q] t @ Q { @ P { ( string_from `a nested field handed to a sink, long enough` ) 1 } 2 } )
    ~ x t { ( gone . . x inner name ) }
    ^ 0
}
