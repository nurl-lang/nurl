// wrapper_of_a_callee_leaving_a_holder_viewing_an_arena_element_then_the_arena_cleared: agora #383 — the same through a wrapper that hands both on with the holder first (`h>^k` carried into the wrapper's answer at its own indices)
// main 87895b72: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #383: the same through a wrapper that hands both on with the holder first (`h>^k` carried into the wrapper's answer at its own indices)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}
@ put_through ( Vec s ) idx ( Vec String ) arena String key → v {
    ( put arena idx key )
}
@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    : ( Vec s ) idx ( vec_new [s] )
    ( put_through idx arena ( string_from `the first key, long enough for the heap` ) )
    ( vec_clear [String] arena )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
