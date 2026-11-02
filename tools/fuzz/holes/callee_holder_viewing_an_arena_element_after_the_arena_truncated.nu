// callee_holder_viewing_an_arena_element_after_the_arena_truncated: agora #383 — as callee_holder_viewing_an_arena_element_after_the_arena_cleared, the arena truncated to nothing
// Closed: the element pair's dependency ends when the arena's elements are dropped (agora #383).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #383: as callee_holder_viewing_an_arena_element_after_the_arena_cleared, the arena truncated to nothing
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
    ( vec_truncate [String] arena 0 )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
