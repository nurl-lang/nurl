// holder_of_a_slice_and_an_element_view_built_by_a_callee_kept_past_the_element_grown: as …_kept_past_the_element_grown_in_place, the holder built by a callee
// Closed on main by 2026-11-15 (agora #402): the callee's answer ties the holder to `arena` directly and through its element; the in-place growth ends it.
// main 8ca9248c: accepted (heap-use-after-free).
// map: §2.10 | A2 | rejected | - | agora #402: the holder of a slice and an element view built by a callee, the element grown in place (R4)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hd { ( Slice String ) sl s v }

@ mk ( Vec String ) a → Hd { ^ @ Hd { ( slice_from_vec [String] a ) ( string_data ( vec_at [String] a 0 ) ) } }

@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    ( vec_push [String] arena ( string_from `an element, short` ) )
    : Hd h ( mk arena )
    : String x ( vec_at [String] arena 0 )
    ( string_push_str x ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println . h v )
    ^ 0
}
