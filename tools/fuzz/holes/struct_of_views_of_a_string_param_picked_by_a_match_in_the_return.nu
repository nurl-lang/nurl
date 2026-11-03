// struct_of_views_of_a_string_param_picked_by_a_match_in_the_return: a struct of views of the String param picked by a ?? written in the return.
// Closed: the walk's answer covers a view or a struct of views handed back too (bck_ret_view_check notes it, not only an owner of views): codegen's answer for a bare view (retlend / retptr) does not reach one picked by a join or a match, bound first, or made in a value block (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | a struct of views of the String parameter picked by a `??` written in the return
$ `stdlib/core/string.nu`

: W { s v i n }

@ mk String s i c → W {
    : ?i o ? == c 0 @ ?i { T 1 } @ ?i { F }
    ^ ?? o { T x → @ W { ( string_data s ) x } F → @ W { `static` 0 } }
}

@ main → i {
    : ~ W hold @ W { `x` 0 }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s 0 )
    }
    ( nurl_println . hold v )
    ^ 0
}
