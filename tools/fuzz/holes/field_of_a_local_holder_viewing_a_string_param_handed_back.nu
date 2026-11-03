// field_of_a_local_holder_viewing_a_string_param_handed_back: a local struct's Vec s field, filled with a view of the String param, handed back as `^ . b h`.
// Closed: a field read handed back (`^ . b h`, or the body falling off with it) carries its source expression to the walk (gen_ret's __ret_exp takes TT_DOT), so what the field holds views of is the function's g_fn_rviews answer, and a view of a local is refused where it is handed back (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | a local struct's Vec s field, filled with a view of the String parameter, handed back as `^ . b h`, kept past the String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: B { ( Vec s ) h i n }

@ mk String s → ( Vec s ) {
    : ~ B b @ B { ( vec_new [s] ) 0 }
    ( vec_push [s] . b h ( string_data s ) )
    ^ . b h
}

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
