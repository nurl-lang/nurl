// closure_over_a_vec_at_binding_of_a_local_vec_handed_back: agora #483 — a function hands back a closure over a `vec_at` binding of its LOCAL Vec, released when it returns
// Closed: a closure holding a copy of the handle in an element of a local, `~^t`, handed back is refused as a view of it is (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding of a local Vec handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkreader → ( @ i ) {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string its function frees before the closure runs` ) )
    : String e ( vec_at [String] t 0 )
    : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
    ^ f
}

@ main → i {
    : ( @ i ) g ( mkreader )
    ( nurl_println_int ( g ) )
    ^ 0
}
