// view_param_through_self_recursion_with_long_lived_sources: agora #370 — guard: the same self-recursive callee, its sources living as long as the holder
// Runs clean: a view the caller passed and kept by a callee is no move of the parameter (agora #370).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #370: guard: the same self-recursive callee, its sources living as long as the holder
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
    : String inner ( string_from `the inner string, which lives as long as the holder` )
    ( rec4 w ( string_data outer ) ( string_data inner ) 1 )
    ( nurl_println . w v )
    ^ 0
}
