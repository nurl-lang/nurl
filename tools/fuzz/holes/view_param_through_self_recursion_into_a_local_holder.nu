// view_param_through_self_recursion_into_a_local_holder: agora #370 — a self-recursive callee hands a local holder and swapped view parameters to itself, then = w lh
// Closed: a view the caller passed (a pv_ parameter) stands for what it points into in the callee's walk, so the callee's answer has the pair h>k and the caller ties the holder argument to the view argument's sources (agora #370).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #370: a self-recursive callee hands a local holder and swapped view parameters to itself, then = w lh
$ `stdlib/core/string.nu`

: W { s v }

@ rec4 inout W w s a s b i n → v {
    ? > n 0 {
        : ~ W lh @ W { `x` }
        ( rec4 lh b a - n 1 )
        = w lh
    } { = w @ W { a } }
}

@ main → i {
    : String outer ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { `literal` }
    {
        : String inner ( string_from `the inner string, freed at the end of its block` )
        ( rec4 w ( string_data outer ) ( string_data inner ) 1 )
    }
    ( nurl_println . w v )
    ^ 0
}
