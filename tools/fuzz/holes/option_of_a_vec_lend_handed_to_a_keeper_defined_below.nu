// option_of_a_vec_lend_handed_to_a_keeper_defined_below: agora #459 — `( unv ( maybev o 0 ) )`, `unv` taking its `?( Vec String )` over, defined below its caller
// Closed: a call's result that lends on some runs, handed to a callee not compiled yet, is copied on those runs where the callee takes it over (consume_flag, agora #459).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: an option of a Vec lent to a keeper defined below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mkv → ?( Vec String ) { : ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `an element long enough for the heap` ) ) ^ @ ?( Vec String ) { T v } }

@ maybev ? ( Vec String ) a i k → ?( Vec String ) { ? == k 0 { ^ a } {} ^ ( mkv ) }

@ main → i {
    : ?( Vec String ) o ( mkv )
    : ( Vec String ) v ( unv ( maybev o 0 ) )
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    ?? o { T w → { ( nurl_println ( string_data ( vec_at [String] w 0 ) ) ) } F → {} }
    ^ 0
}

@ unv ? ( Vec String ) o → ( Vec String ) { ^ ?? o { T v → v F → ( vec_new [String] ) } }
