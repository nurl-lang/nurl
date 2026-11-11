// view_of_a_payload_of_a_result_given_the_binding_of_a_call_that_is_fresh_or_lent_handed_back: agora #679 — `pick` assigns its `: ~` binding the binding of a call that is fresh or lent per call (`: ?S t ( inner v own ) = o t ^ o`); its caller hands back a view of the payload
// Closed: a binding that can be assigned again may own what any value it was ever given hands over, so `pick` answers for storage of its own and its caller's binding may own its value.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #679: `pick` assigns its `: ~` binding the binding of a call that is fresh or lent per call (`: ?S t ( inner v own ) = o t ^ o`); its caller hands back a view of the payload
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ inner ( Vec S ) v b own → ?S {
    ? own { ^ @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
    : ?S found ( vec_get [S] v 0 )
    ^ found
}

@ pick ( Vec S ) v b own → ?S {
    : ~ ? S o @ ?S { F @ S { ( string_new ) 0 } }
    : ?S t ( inner v own )
    = o t
    ^ o
}

@ f ( Vec S ) v b own → s {
    : ?S o ( pick v own )
    ?? o {
        T e → { ^ ( string_data . e name ) }
        F → { ^ `` }
    }
    ^ ``
}

@ main → i {
    : ~ ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks `a lent string long enough to live on the heap, for sure` ) )
    ( nurl_println ( f v T ) )
    ( nurl_println ( f v F ) )
    ^ 0
}
