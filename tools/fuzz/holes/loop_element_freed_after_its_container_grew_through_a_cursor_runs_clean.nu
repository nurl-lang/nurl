// loop_element_freed_after_its_container_grew_through_a_cursor_runs_clean: agora #587 — the container grows through a cursor, then `( string_free x )` and `break`: the slot emptied is the one in the moved buffer
// Closed: the field (or the element) is emptied in the element's slot, found through the Vec's control block where the buffer is at that moment (agora #587).
// main 005f953: AddressSanitizer: heap-use-after-free (the container released it again, or the old buffer was written).
// map: §2.5 | A2 | runs-clean | - | agora #587: the container grows through a cursor, then `( string_free x )` and `break`: the slot emptied is the one in the moved buffer
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    ~ x t {
        : ~ i n 0
        ~ < n 64 { ( vec_push [String] cur ( string_from `grow` ) ) = n + n 1 }
        ( string_free x )
        break
    }
    ^ 0
}
