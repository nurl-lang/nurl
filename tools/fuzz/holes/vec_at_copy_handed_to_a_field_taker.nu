// vec_at_copy_handed_to_a_field_taker: a vec_at copy handed whole to a function that releases one of its
// fields: the function only kept its parameter, so the caller handed over a
// borrow, and the Vec released the field again.
// Closed: the function's parameter is an inferred `sink` (h389), so a borrow
// handed to it is rejected (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | rejected | h396 | a vec_at copy handed whole to a function that takes a field of its parameter: kept only, so the borrow went over and the Vec released the field again; the parameter is a sink now
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f Q q → v { ( string_free . q name ) }

@ main → i {
    : ( Vec Q ) vs ( vec_new [Q] )
    ( vec_push [Q] vs @ Q { ( mk ) ( mk ) } )
    : Q e ( vec_at [Q] vs 0 )
    ( f e )
    ( vec_free [Q] vs )
    ^ 0
}
