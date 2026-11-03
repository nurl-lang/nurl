// struct_of_views_of_a_string_param_as_a_value_block_tail_literal: a struct of views of the String param as a value block's tail literal, handed back.
// Closed: the walk's answer covers a view or a struct of views handed back too (bck_ret_view_check notes it, not only an owner of views): codegen's answer for a bare view (retlend / retptr) does not reach one picked by a join or a match, bound first, or made in a value block (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | a struct of views of the String parameter as a value block's tail literal, handed back
$ `stdlib/core/string.nu`

: W { s v i n }

@ mk String s → W {
    ^ {
        : i z 1
        @ W { ( string_data s ) z }
    }
}

@ main → i {
    : ~ W hold @ W { `x` 0 }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println . hold v )
    ^ 0
}
