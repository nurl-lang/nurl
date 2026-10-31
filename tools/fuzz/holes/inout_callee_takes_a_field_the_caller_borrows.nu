// inout_callee_takes_a_field_the_caller_borrows: an element borrowed out of `. r xs`, then `( g r )` with `g inout R
// r` handing `. r xs` to a `sink`: the field is emptied in the caller's
// struct, but `g`'s replacement summary had no entry, so the borrow outlived
// it.
// Closed: a field of an `inout` parameter handed to any parameter records an
// `s` replacement edge, resolved on the callee's final sink summary (agora
// #147).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.4 | A1 | rejected | h417 | an inout callee handed a field of its parameter to a sink; the caller's element borrow of that field outlived it (UAF); a replacement edge resolved on the callee's sink summary
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { ( Vec String ) xs i n }

@ take_any [T] sink T x → v {}

@ g inout R r → v { ( take_any [( Vec String )] . r xs ) }

@ main → i {
    : ~ R r @ R { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    : String e ( vec_at [String] . r xs 0 )
    ( g r )
    ( nurl_println ( string_data e ) )
    ^ 0
}
