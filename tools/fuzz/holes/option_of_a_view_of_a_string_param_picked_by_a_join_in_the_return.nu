// option_of_a_view_of_a_string_param_picked_by_a_join_in_the_return: an option of a view of the String param picked by a join written in the return
// Closed: the walk's answer covers a view or a struct of views handed back too (bck_ret_view_check notes it, not only an owner of views): codegen's answer for a bare view (retlend / retptr) does not reach one picked by a join or a match, bound first, or made in a value block (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | an option of a view of the String parameter picked by a join written in the return
$ `stdlib/core/string.nu`

: W { s v i n }

@ mk String s i c → ?s {
    ^ ? == c 0 @ ?s { T ( string_data s ) } @ ?s { F }
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
