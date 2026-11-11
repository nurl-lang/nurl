// bare_s_view_of_a_match_payload_handed_back_read_before_its_vec_is_cleared_runs_clean: agora #578 — a bare `s` view of a `??` value join's payload handed back, read by the caller before it clears p
// Control for agora #578: the lend refuses only a use after the clear.
// map: §2.10 | A2 | runs-clean | - | agora #578: a bare `s` view of a `??` value join's payload handed back, read by the caller before it clears p
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first_str ( Vec String ) p → s {
    ^ ?? ( vec_get [String] p 0 ) {
        T e → ( string_data e )
        F → ``
    }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( first_str t )
    ( nurl_println v )
    ( vec_clear [String] t )
    ^ 0
}
