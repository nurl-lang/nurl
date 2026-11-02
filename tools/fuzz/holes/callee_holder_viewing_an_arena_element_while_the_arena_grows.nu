// callee_holder_viewing_an_arena_element_while_the_arena_grows: agora #383 — guard: the arena only grows (its own buffer moves, the elements' do not), so the holder's views of the elements stay good
// Runs clean: an element pair's dependency survives the argument's own buffer moving (agora #383).
// main: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #383: guard: the arena only grows (its own buffer moves, the elements' do not), so the holder's views of the elements stay good
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
    ( put arena idx ( string_from `the second key, long enough for the heap` ) )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ( nurl_println ( vec_at [s] idx 1 ) )
    ^ 0
}
