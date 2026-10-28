// H416: a `~ x . r xs` loop's body handed the field it iterates to a `sink`
// (`( take_any . r xs )`), then read `x`: the foreach rule asked only for
// container mutators and `inout` arguments.
// Closed: a loop container handed to a callee that takes it is rejected,
// inline and on the callee's final summary (agora #147).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { ( Vec String ) xs i n }

@ take_any [T] sink T x → v {}

@ main → i {
    : R r @ R { ( vec_new [String] ) 0 }
    ( vec_push [String] . r xs ( mk ) )
    ~ x . r xs {
        ( take_any [( Vec String )] . r xs )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
