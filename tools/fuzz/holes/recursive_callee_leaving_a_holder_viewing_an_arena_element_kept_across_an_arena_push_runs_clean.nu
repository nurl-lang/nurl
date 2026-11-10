// recursive_callee_leaving_a_holder_viewing_an_arena_element_kept_across_an_arena_push_runs_clean: agora #383 — the recursive twin, the arena only grown
// Control for agora #383.
// map: §2.10 | A2 | runs-clean | - | agora #383: the recursive twin, the arena only grown
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
@ put_n ( Vec String ) arena ( Vec s ) idx i n → v {
    ? <= n 0 { ^ } {}
    ( vec_push [String] arena ( string_from `a key long enough to live on the heap` ) )
    ? == n 1 {
        : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
        ( vec_push [s] idx ( string_data e ) )
    } { ( put_n arena idx - n 1 ) }
}
@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    : ( Vec s ) idx ( vec_new [s] )
    ( put_n arena idx 3 )
    ( vec_push [String] arena ( string_from `one more key, long enough for the heap` ) )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
