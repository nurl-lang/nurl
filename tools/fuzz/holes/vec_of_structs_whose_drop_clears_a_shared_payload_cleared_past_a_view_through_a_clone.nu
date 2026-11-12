// vec_of_structs_whose_drop_clears_a_shared_payload_cleared_past_a_view_through_a_clone: a `( Vec H )` whose `: H { ( Rc ( Vec u ) ) a }` has a `% Drop` that clears and shrinks `( rc_get . h a )`, holding `r`, cleared with `vec_clear` while a slice of the payload is taken through `r2`
// Closed: a library dropper handed a container whole drops handles, which a view through another handle outlives — unless dropping an element runs the program's own `% Drop`, which may reach anything (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a Vec of structs whose Drop clears a shared payload, cleared past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec H ) hs ( vec_new [H] )
    ( vec_push [H] hs @ H { r } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( vec_clear [H] hs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
