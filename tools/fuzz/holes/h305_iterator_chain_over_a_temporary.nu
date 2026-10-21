// H305: an iterator chain built over a temporary source iterator (`iter_map ( iter_from_vec v ) f`) did not hold a view of `v`: the inner iterator moved into the `sink` combinator, whose result was counted only for the views among its argument's names (h304), so releasing `v` left the chain reading the freed elements. Binding the inner iterator first was already rejected.
// Closed: as h304 — the inner call's lends (`iter_from_vec`'s `retclo`, h299) are sources of the chain.
// main (before this PR): AddressSanitizer reported heap-use-after-free in vec_get, called through the chain.
$ `stdlib/std/iter.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ ?i i ) it ( iter_map [i i] ( iter_from_vec [i] v ) \ i x → i { ^ * x 2 } )
    ( vec_free [i] v )
    : ?i g ( it 0 )
    ?? g { T x → { ( nurl_println_int x ) } F → { ( nurl_println `none` ) } }
    ^ 0
}
