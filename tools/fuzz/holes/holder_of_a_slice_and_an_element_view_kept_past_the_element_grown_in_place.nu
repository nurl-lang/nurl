// holder_of_a_slice_and_an_element_view_kept_past_the_element_grown_in_place: a holder of a slice of `arena` and of a view of its element's bytes, read after the element grew in place
// Closed on main by 2026-11-15 (agora #402): a dependency held both directly and through an element is ended by the element's in-place growth.
// main 8ca9248c: accepted (heap-use-after-free).
// map: §2.10 | A2 | rejected | - | agora #402: one dependency held directly and through an element, the element grown in place (R5)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hd { ( Slice String ) sl s v }

@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    ( vec_push [String] arena ( string_from `an element, short` ) )
    : Hd h @ Hd { ( slice_from_vec [String] arena ) ( string_data ( vec_at [String] arena 0 ) ) }
    : String x ( vec_at [String] arena 0 )
    ( string_push_str x ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println . h v )
    ^ 0
}
