// payload_matched_straight_out_of_a_call_that_is_fresh_or_lent_handed_back_in_an_option_literal: agora #679 — `?? ( pick v own ) { T e → { ^ @ ?S { T e } } … }`: the payload of a call that is fresh or lent per call, wrapped in a literal and handed back as the function's own; lent, the caller clears the Vec and reads freed memory
// Closed: such a payload may be the call's own storage, so the literal is refused as a view of a local; hand the call's result back as it is (`^ ( pick v own )`).
// main a9be57b: accepted; heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #679: `?? ( pick v own ) { T e → { ^ @ ?S { T e } } … }`: the payload of a call that is fresh or lent per call, wrapped in a literal and handed back as the function's own; lent, the caller clears the Vec and reads freed memory
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ pick ( Vec S ) v b own → ?S {
    ? own { ^ @ ?S { T ( mks `an owned string long enough to live on the heap, for sure` ) } } {}
    ^ ( vec_get [S] v 0 )
}

@ f ( Vec S ) v b own → ?S {
    ?? ( pick v own ) {
        T e → { ^ @ ?S { T e } }
        F → {}
    }
    ^ @ ?S { F }
}

@ main → i {
    : ~ ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va ( mks `a lent string long enough to live on the heap, for sure` ) )
    : ?S w ( f va F )
    ( vec_clear [S] va )
    ?? w {
        T x → { ( nurl_println ( string_data . x name ) ) }
        F → {}
    }
    ^ 0
}
