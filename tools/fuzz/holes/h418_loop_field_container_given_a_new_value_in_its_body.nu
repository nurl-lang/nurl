// H418: a `~ x . r xs` loop's body gave the field it iterates a new value
// (`= . r xs ( vec_new … )`), releasing the Vec under the loop.
// Closed: an assignment whose target is a loop container, a field of one or
// the struct it belongs to is rejected (agora #147).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { ( Vec String ) xs i n }

@ take_any [T] sink T x → v {}

@ main → i {
    : R r @ R { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    ~ x . r xs {
        = . r xs ( vec_new [String] )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
