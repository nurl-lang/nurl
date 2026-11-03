// struct_of_views_of_a_string_param_from_a_value_block_handed_back: a struct of views (class 2) bound inside a value block from the String param, the block's tail its name, handed back.
// Closed: the walk's answer covers a view or a struct of views handed back too (bck_ret_view_check notes it, not only an owner of views): codegen's answer for a bare view (retlend / retptr) does not reach one picked by a join or a match, bound first, or made in a value block (agora #422).
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | a struct of views of the String parameter bound inside a value block, the block's tail its name
$ `stdlib/core/string.nu`

: W { s v i n }

@ mk String s → W {
    ^ {
        : W w @ W { ( string_data s ) 1 }
        w
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
