$ `stdlib/core/vec.nu`

// The moved Vec is the closure's own argument, read in its body: the
// indirect call itself must refuse it (clo_called_on_a_moved_vec_refused.nu
// is refused earlier, at its argument's `vec_len`).
@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ main → i {
    : ( @ i ( Vec i ) ) f \ ( Vec i ) x → i { ^ ( vec_len [i] x ) }
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 1 )
    : i n ( eat w )
    ^ + n ( f w )
}
