// H394: a field of a vec_at copy handed to `string_free`: only the copy was
// emptied, and the Vec released the element's field again.
// Closed: a field emptied only in a borrowing binding's copy (a vec_at copy,
// a field viewer) handed to a callee that takes it is rejected — gen_call's
// `pendfx` row (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name }

@ main → i {
    : ( Vec Q ) vs ( vec_new [Q] )
    ( vec_push [Q] vs @ Q { ( mk ) } )
    : Q e ( vec_at [Q] vs 0 )
    ( string_free . e name )
    ( vec_free [Q] vs )
    ^ 0
}
