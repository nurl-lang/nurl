// element_grown_inline_in_a_loop_past_a_slice_taken_before: agora #349 — the inline lend `( vec_at vv k )` grown in a loop over every index; a slice of `vv[0]` kept from before the loop
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element grown inline in a loop past a slice taken before
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    : ~ i k 0
    ~ < k ( vec_len [( Vec u )] vv ) {
        ( vec_reserve [u] ( vec_at [( Vec u )] ( id2 vv ) k ) 4096 )
        = k + k 1
    }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

@ id2 ( Vec ( Vec u ) ) v → ( Vec ( Vec u ) ) {
    ^ v
}
