// generic_struct_of_a_loop_element_view_handed_back_read_past_the_container: agora #471 — `@ mkg [A] ( Vec String ) p A d → W` hands back `@ W { ( string_data x ) 1 }` from `~ x p`; its instance's caller clears its Vec, then reads `. w v`
// Closed: a caller waits for a callee not walked yet whose result is a struct, an option or an enum of views (class 2), as for a bare `s` (__rv_waits; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a generic struct of a loop element view handed back, read past the container cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v i n }

@ mkg [A] ( Vec String ) p A d → W {
    ~ x p { ^ @ W { ( string_data x ) 1 } }
    ^ @ W { `none` 0 }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : W w ( mkg [i] t 0 )
    ( vec_clear [String] t )
    ( nurl_println . w v )
    ^ 0
}
