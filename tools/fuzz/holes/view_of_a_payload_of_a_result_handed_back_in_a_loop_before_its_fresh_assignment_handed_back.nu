// view_of_a_payload_of_a_result_handed_back_in_a_loop_before_its_fresh_assignment_handed_back: agora #679 — `pick` hands its `: ~` binding back at the top of a loop round whose previous round assigned a fresh option over the lend it held; its caller hands back a view of the payload
// Closed: a binding that can be assigned again may own what any value it was ever given hands over, so `pick` answers for storage of its own and its caller's binding may own its value.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #679: `pick` hands its `: ~` binding back at the top of a loop round whose previous round assigned a fresh option over the lend it held; its caller hands back a view of the payload
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    : ~ ? S o ( vec_get [S] v 0 )
    : ~ i k 0
    ~ < k 2 {
        ? == k 1 { ^ o } {}
        ? own { = o @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
        = k + k 1
    }
    ^ @ ?S { F @ S { ( string_new ) 0 } }
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
