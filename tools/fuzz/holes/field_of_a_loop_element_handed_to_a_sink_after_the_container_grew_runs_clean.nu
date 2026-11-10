// field_of_a_loop_element_handed_to_a_sink_after_the_container_grew_runs_clean: agora #587 — the container grows through a cursor, then `( gone . x name )` and `break`: the slot is found where the buffer is now
// Closed: the field (or the element) is emptied in the element's slot, found through the Vec's control block where the buffer is at that moment (agora #587).
// main 005f953: AddressSanitizer: heap-use-after-free (the container released it again, or the old buffer was written).
// map: §2.5 | A2 | runs-clean | - | agora #587: the container grows through a cursor, then `( gone . x name )` and `break`: the slot is found where the buffer is now
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: Q { P inner i k }

@ gone sink String a → v {}

@ main → i {
    : ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a struct element whose field is handed to a sink` ) 1 } )
    ( vec_push [P] t @ P { ( string_from `a second struct element, long enough for the heap` ) 2 } )
    : ~ ( Vec P ) cur t
    ~ x t {
        : ~ i n 0
        ~ < n 64 { ( vec_push [P] cur @ P { ( string_from `grow` ) n } ) = n + n 1 }
        ( gone . x name )
        break
    }
    ^ 0
}
