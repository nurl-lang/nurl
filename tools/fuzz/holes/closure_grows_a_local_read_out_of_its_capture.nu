// closure_grows_a_local_read_out_of_its_capture: the local's buffer grown by vec_reserve while a slice of it is live.
// Closed: in a closure body, a handle local read out of a capture (an element a lending call lends, a field, a copy of one) reaches that capture, so what a call does to the local is an effect of running the closure on the capture, as for the direct form (g_clo_deriv, __clo_effect_note; agora #353).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #353: the local's buffer grown by vec_reserve while a slice of it is live
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    : ( @ v ) grow \ → v { : ( Vec u ) e ( vec_at [( Vec u )] vv 0 ) ( vec_reserve [u] e 4096 ) }
    ( grow )
    ( nurl_println_int ( slice_at [u] sl 0 ) )
    ^ 0
}
