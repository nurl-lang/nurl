// field_of_a_loop_element_freed_then_the_container_dropped_runs_clean: agora #587 — `~ r rs { ( string_free . r name ) }`: the field is emptied in the element's slot, rs drops clean
// Closed: the field (or the element) is emptied in the element's slot, found through the Vec's control block where the buffer is at that moment (agora #587).
// main 005f953: AddressSanitizer: heap-use-after-free (the container released it again, or the old buffer was written).
// map: §2.5 | A2 | runs-clean | - | agora #587: `~ r rs { ( string_free . r name ) }`: the field is emptied in the element's slot, rs drops clean
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

: R { String name i n }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i done 0
    : ~ ( Vec R ) rs ( vec_new [R] )
    ( vec_push [R] rs @ R { ( string_from `a name long enough for a heap buffer here` ) 0 } )
    ( vec_push [R] rs @ R { ( string_from `a second name long enough for a heap buffer` ) 0 } )
    ~ r rs { ( string_free . r name ) }
    ^ 0
}
