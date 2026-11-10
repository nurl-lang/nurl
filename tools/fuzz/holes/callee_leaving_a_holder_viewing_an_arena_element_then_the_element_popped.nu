// callee_leaving_a_holder_viewing_an_arena_element_then_the_element_popped: agora #383 — the same, then `( vec_pop arena )`, the popped element dropped
// main 87895b72: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #383: the same, then `( vec_pop arena )`, the popped element dropped
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}

@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    : ( Vec s ) idx ( vec_new [s] )
    ( put arena idx ( string_from `the first key, long enough for the heap` ) )
    ( vec_pop [String] arena )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
