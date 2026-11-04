// struct_of_a_loop_element_view_over_a_param_handed_back_by_a_callee_below: agora #471 — `@ mk ( Vec String ) p → W { ~ x p { ^ @ W { ( string_data x ) 1 } } … }` below its caller; the caller clears its Vec, then reads `. w v`
// Closed: a caller waits for a callee not walked yet whose result is a struct, an option or an enum of views (class 2), as for a bare `s` (__rv_waits; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a struct of a loop element view over a parameter, handed back by a callee below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v i n }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : W w ( mk t )
    ( vec_clear [String] t )
    ( nurl_println . w v )
    ^ 0
}

@ mk ( Vec String ) p → W {
    ~ x p { ^ @ W { ( string_data x ) 1 } }
    ^ @ W { `none` 0 }
}
