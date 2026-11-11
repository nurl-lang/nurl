// view_of_a_payload_of_a_bound_result_that_is_fresh_or_lent_handed_back: agora #679 — `pick` hands back a fresh option on one path and `vec_get`'s lend on the other; its caller binds the result, matches it and hands back a view of the payload — freed with the binding on the fresh path
// Closed: a binding bound to a call that lends on one call and hands over storage of its own on another borrows the argument and may own its value besides; a view of it handed back is a view of a local.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #679: `pick` hands back a fresh option on one path and `vec_get`'s lend on the other; its caller binds the result, matches it and hands back a view of the payload — freed with the binding on the fresh path
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    ? own { ^ @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
    : ?S found ( vec_get [S] v 0 )
    ^ found
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
