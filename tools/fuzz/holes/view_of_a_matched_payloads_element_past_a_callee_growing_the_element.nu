// view_of_a_matched_payloads_element_past_a_callee_growing_the_element: a slice of an element of a Vec-of-Vec payload cursor, the option handed to a callee growing that element
// Closed: a callee growing the option's payload ends the views of a payload cursor over it, of a cursor over that cursor, and of the cursor's field paths; one moving only an element's buffer ends only the views through the elements (agora #816's review).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #816: a view of a matched payload's element past a callee growing the element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

@ wi ? ( Vec ( Vec u ) ) o → v {
    ?? o { T p → { : ( Vec u ) e ( vec_at [( Vec u )] p 0 ) ( vec_reserve [u] e 4096 ) } F → {} }
}

@ main → i {
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    : ( Vec ( Vec u ) ) xs ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] xs inner )
    : ?( Vec ( Vec u ) ) o @ ?( Vec ( Vec u ) ) { T xs }
    ?? o {
        T q → {
            : ( Vec u ) e ( vec_at [( Vec u )] q 0 )
            : ( Slice u ) sl ( slice_from_vec [u] e )
            ( wi o )
            ( nurl_println_int # i ( slice_at [u] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
