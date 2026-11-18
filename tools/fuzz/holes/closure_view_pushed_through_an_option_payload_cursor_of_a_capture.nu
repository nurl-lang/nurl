// closure_view_pushed_through_an_option_payload_cursor_of_a_capture: inside a closure, a view of a closure local pushed through `?? ov { T w → ( vec_push w … ) }` of a captured option
// Closed (agora #395): inside a closure, a store through a borrow asks the capture rule (bck_clo_cap_view_diag) of every holder it lands in — the owner a borrow of a capture is read out of (__bck_store_owners), the roots an unbound call container lends (__bck_store_roots) — not only of the container's own root, as storing it into the capture by name does (agora #312). A2: a capture by name holds no views (CapsOK).
// main 6005efcb: AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #395: inside a closure, a view of a closure local pushed through `?? ov { T w → ( vec_push w … ) }` of a captured option
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ?( Vec s ) ov @ ?( Vec s ) { T ( vec_new [s] ) }
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string freed when the closure returns, long enough for the heap` )
        ?? ov { T w → ( vec_push [s] w ( string_data loc ) ) F → {} }
    }
    ( f )
    ?? ov { T w → ( nurl_println ( vec_at [s] w 0 ) ) F → {} }
    ^ 0
}
