// drop_changing_a_shared_payload_through_a_helper_released_at_a_block_end: a `K` whose `drop` hands its `H` field to a helper that clears the payload
// Closed: releasing a value with no call — its block's end, the old value of `=`, a temporary its statement or call is done with, a field's old value, a `sink` parameter its callee lets go — runs each `% Drop` of the program's own its type holds, and the walk sweeps that release as a call of the impl handed the value: what the impl's summary drops, replaces or moves of an Rc's payload ends the views another handle took (agora #766).
// main 5f3d33e: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #766: a K whose drop hands its H field to a helper that clears the payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/core/box.nu`

: H { ( Rc ( Vec u ) ) a }

@ hlp H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) }

% Drop K { @ drop K k → v { ( hlp . k h ) } }

: K { H h }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    { : K k @ K { @ H { r } } }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
