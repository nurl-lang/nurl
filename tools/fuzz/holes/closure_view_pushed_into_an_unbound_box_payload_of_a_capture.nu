// closure_view_pushed_into_an_unbound_box_payload_of_a_capture: inside a closure, a view of a closure local pushed into `( box_get bx )` of a capture, an unbound call as the container
// Closed (agora #395): inside a closure, a store through a borrow asks the capture rule (bck_clo_cap_view_diag) of every holder it lands in — the owner a borrow of a capture is read out of (__bck_store_owners), the roots an unbound call container lends (__bck_store_roots) — not only of the container's own root, as storing it into the capture by name does (agora #312). A2: a capture by name holds no views (CapsOK).
// main 6005efcb: AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #395: inside a closure, a view of a closure local pushed into `( box_get bx )` of a capture, an unbound call as the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ main → i {
    : ( Box ( Vec s ) ) bx ( box_new [( Vec s )] ( vec_new [s] ) )
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string freed when the closure returns, long enough for the heap` )
        ( vec_push [s] ( box_get [( Vec s )] bx ) ( string_data loc ) )
    }
    ( f )
    ( nurl_println ( vec_at [s] ( box_get [( Vec s )] bx ) 0 ) )
    ^ 0
}
