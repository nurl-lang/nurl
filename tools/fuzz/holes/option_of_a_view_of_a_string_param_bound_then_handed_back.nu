// option_of_a_view_of_a_string_param_bound_then_handed_back: an option of a view of the String param bound first, handed back by name (class 2), kept past the String.
// Closed: the walk's answer covers a view or a struct of views handed back too (bck_ret_view_check notes it, not only an owner of views): codegen's answer for a bare view (retlend / retptr) does not reach one picked by a join or a match, bound first, or made in a value block (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | an option of a view of the String parameter bound first, handed back by name, kept past the String
$ `stdlib/core/string.nu`

@ mk String s i c → ?s {
    : ?s o ? == c 0 @ ?s { T ( string_data s ) } @ ?s { F }
    ^ o
}

@ main → i {
    : ~ ? s hold @ ?s { F }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s 0 )
    }
    ?? hold { T x → ( nurl_println x ) F → {} }
    ^ 0
}
