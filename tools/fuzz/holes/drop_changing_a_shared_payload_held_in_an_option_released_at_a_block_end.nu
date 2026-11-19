// drop_changing_a_shared_payload_held_in_an_option_released_at_a_block_end: a `?H` holding the `H`, released at its block's end
// Closed: releasing a value with no call — its block's end, the old value of `=`, a temporary its statement or call is done with, a field's old value, a `sink` parameter its callee lets go — runs each `% Drop` of the program's own its type holds, and the walk sweeps that release as a call of the impl handed the value: what the impl's summary drops, replaces or moves of an Rc's payload ends the views another handle took (agora #766).
// main 5f3d33e: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #766: a ?H holding the H, released at its block's end
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
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ? > ( slice_len [u] sl ) 0 { : ?H o @ ?H { T @ H { r } } ( nurl_println_int 1 ) } {}
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
