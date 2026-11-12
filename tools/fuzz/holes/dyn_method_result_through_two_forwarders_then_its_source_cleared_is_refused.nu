// dyn_method_result_through_two_forwarders_then_its_source_cleared_is_refused: a forwarder of a forwarder of the dyn call
// Closed: agora #699 (the virtual's callers are solved again as its union grows).
// main 4dfee821: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #699: two forwarders of a dyn method result lend what the impls lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

% Src [T] {
    @ first T self ( Vec S ) v → S
}

: A { i n }
: B { i n }

% Src A { @ first A a ( Vec S ) v → S { ^ ( vec_at [S] v 0 ) } }

@ viaobj %Src o ( Vec S ) v → S { ^ ( first o v ) }

@ via2 %Src o ( Vec S ) v → S { ^ ( viaobj o v ) }

@ main → i {
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks `an element string long enough for a heap buffer` ) )
    : A aa @ A { 1 }
    : %Src o ( dyn Src aa )
    : S e ( via2 o va )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
