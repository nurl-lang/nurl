// enum_of_a_loop_element_view_over_a_param_handed_back_by_a_callee_below: agora #471 — `@ first ( Vec String ) p → Tok`, defined below its caller, hands back `@ Tok { Word ( string_data x ) }` from `~ x p`; the caller clears its Vec, then reads the payload
// Closed: a caller waits for a callee not walked yet whose result is a struct, an option or an enum of views (class 2), as for a bare `s` (__rv_waits; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: an enum of a loop element view over a parameter, handed back by a callee below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading the payload` ) )
    : Tok k ( first t )
    ( vec_clear [String] t )
    ?? k { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) }
    ^ 0
}

@ first ( Vec String ) p → Tok {
    ~ x p { ^ @ Tok { Word ( string_data x ) } }
    ^ @ Tok { Num 0 }
}
