// vec_at_result_handed_to_a_field_taker: as h396, the vec_at call written as the argument.
// Closed: as h396: a call's lent result handed to a `sink` is handed a copy
// (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | runs-clean | h397 | as h396, the vec_at call as the argument: the sink is handed a copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ f Q q → v { ( string_free . q name ) }

@ main → i {
    : ( Vec Q ) vs ( vec_new [Q] )
    ( vec_push [Q] vs @ Q { ( mk ) ( mk ) } )
    ( f ( vec_at [Q] vs 0 ) )
    ( vec_free [Q] vs )
    ^ 0
}
