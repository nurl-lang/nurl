// callee_leaving_a_holder_viewing_an_arena_element_then_the_arena_cleared: agora #383 — `put arena idx key` pushes key into arena, binds `: String e ( vec_at arena n )` and pushes `string_data e` into idx; the caller clears arena and reads idx (the PO's arena_clear_bound)
// main 87895b72: accepted; heap-use-after-free (a view of an argument's elements' buffers, `vdi_`, gave the callee's answer no pair).
// map: §2.10 | A2 | rejected | - | agora #383: `put arena idx key` pushes key into arena, binds `: String e ( vec_at arena n )` and pushes `string_data e` into idx; the caller clears arena and reads idx (the PO's arena_clear_bound)
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
    ( vec_clear [String] arena )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
