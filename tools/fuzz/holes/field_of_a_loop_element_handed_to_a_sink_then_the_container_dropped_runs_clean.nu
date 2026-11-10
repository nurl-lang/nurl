// field_of_a_loop_element_handed_to_a_sink_then_the_container_dropped_runs_clean: agora #587 — `~ x t { ( gone . x name ) }`, gone taking a `sink String`: the field is emptied in the element's slot, t drops clean
// Closed: the field (or the element) is emptied in the element's slot, found through the Vec's control block where the buffer is at that moment (agora #587).
// main 005f953: AddressSanitizer: heap-use-after-free (the container released it again, or the old buffer was written).
// map: §2.5 | A2 | runs-clean | - | agora #587: `~ x t { ( gone . x name ) }`, gone taking a `sink String`: the field is emptied in the element's slot, t drops clean
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ gone sink String a → v {}

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element whose field is handed to a sink` ) 1 } )
    ~ x t { ( gone . x name ) }
    ^ 0
}
