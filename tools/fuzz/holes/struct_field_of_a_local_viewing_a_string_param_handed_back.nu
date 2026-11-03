// struct_field_of_a_local_viewing_a_string_param_handed_back: a local struct holding a P { s w String o } field, filled from the String param, handed back `^ . b p`.
// Closed: a field read handed back (`^ . b h`, or the body falling off with it) carries its source expression to the walk (gen_ret's __ret_exp takes TT_DOT), so what the field holds views of is the function's g_fn_rviews answer, and a view of a local is refused where it is handed back (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | a local struct's P { s w String o } field filled from the String parameter, handed back `^ . b p`
$ `stdlib/core/string.nu`

: P { s w String o }
: B { P p i n }

@ mk String s → P {
    : B b @ B { @ P { ( string_data s ) ( string_from `own` ) } 0 }
    ^ . b p
}

@ main → i {
    : ~ P hold @ P { `x` ( string_from `y` ) }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println . hold w )
    ^ 0
}
