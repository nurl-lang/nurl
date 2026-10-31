// vec_iterator_outlives_its_vec: an iterator over a Vec (`iter_from_vec`) called after the Vec was released read the freed element block — h299 through the standard library.
// Closed: as h299 — `iter_from_vec`'s closure captures the Vec, so its result holds a view of it.
// main (before this PR): AddressSanitizer reported heap-use-after-free in vec_get, called from the iterator.
// map: §2.11 | A2 | rejected | h300 | h299 through iter_from_vec: the iterator called after its Vec was released
$ `stdlib/std/iter.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ ?i i ) it ( iter_from_vec [i] v )
    ( vec_free [i] v )
    : ?i g ( it 0 )
    ?? g { T x → { ( nurl_println_int x ) } F → { ( nurl_println `none` ) } }
    ^ 0
}
