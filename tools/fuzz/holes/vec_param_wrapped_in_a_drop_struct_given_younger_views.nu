// vec_param_wrapped_in_a_drop_struct_given_younger_views: a Vec of views moved into a struct with a destructor, older than the views.
// Closed: a copy of a value that holds views holds them too — what a callee makes of an argument's views (`%k` in g_fn_rviews, `h>%k` in g_fn_vkeeps) is derived from its walk, where a parameter's views stand for themselves (the pseudo `%p`); `mem_dup` hands back what its operand holds; a callee with no walk answer (trusted, library) holds what its arguments hold, A2's heldOfArgs.
// main 4f15689: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #362: a Vec of views moved into a struct with a destructor, older than the views
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: T1 { ( Vec W ) a }

@ wrap ( Vec W ) ws → T1 {
    ^ @ T1 { ws }
}

@ main → i {
    : ( Vec W ) w0 ( vec_new [W] )
    ( vec_push [W] w0 @ W { `literal` } )
    : ~ T1 o ( wrap w0 )
    : String s ( string_from `a string declared after o, so dropped before it at the end of main` )
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { ( string_data s ) } )
    = o ( wrap ws )
    ^ 0
}
