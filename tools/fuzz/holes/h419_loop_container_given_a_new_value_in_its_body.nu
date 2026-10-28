// H419: as h418, a local `~ x xs` loop and `= xs …`.
// Closed: as h418 (agora #147).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ main → i {
    : ~ ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( mk ) )
    ~ x xs {
        = xs ( vec_new [String] )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
