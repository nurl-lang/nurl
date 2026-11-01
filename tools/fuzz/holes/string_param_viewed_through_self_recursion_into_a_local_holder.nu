// string_param_viewed_through_self_recursion_into_a_local_holder: agora #337 — a self-recursive callee hands a local holder and a String parameter to itself, then `= w lh`: its own answer names the pair the recursion makes.
// Closed: a self-call into a local holder whose sources are all parameters is taken as kept, so `= w lh` carries the dependency into the function's own answer (vself_kept, __vk_all_params; agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: self-recursion through a local holder, a String parameter viewed into it
$ `stdlib/core/string.nu`

: W { s v }

@ rec4 inout W w String a String b i n → v {
    ? > n 0 {
        : ~ W lh @ W { `x` }
        ( rec4 lh b a - n 1 )
        = w lh
    } { = w @ W { ( string_data a ) } }
}

@ main → i {
    : String outer ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { `literal` }
    {
        : String inner ( string_from `the inner string, freed at the end of its block` )
        ( rec4 w outer inner 1 )
    }
    ( nurl_println . w v )
    ^ 0
}
