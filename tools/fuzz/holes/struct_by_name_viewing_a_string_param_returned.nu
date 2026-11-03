// struct_by_name_viewing_a_string_param_returned: a struct of a view and an owned field, bound first, handed back by name.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews: `k` a parameter's own storage, `^k` only its elements'), and the caller's result depends on those arguments (bck_sx_ev); a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #442: a struct of a view and an owned field, bound first, handed back by name
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W2 { s t String x }

@ mk String p → W2 {
    : W2 w @ W2 { ( string_data p ) ( string_from `x` ) }
    ^ w
}

@ main → i {
    : ~ W2 hold @ W2 { `a` ( string_from `b` ) }
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println . hold t )
    ^ 0
}
