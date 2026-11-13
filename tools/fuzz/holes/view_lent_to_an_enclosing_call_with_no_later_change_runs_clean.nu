// view_lent_to_an_enclosing_call_with_no_later_change_runs_clean: agora #604's controls — a lent view read by its call where nothing ended it, and a scalar read before the change
// Open: none — each was accepted and clean before, and still is.
// main 3cfdf8a: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #604: `+ ( string_len s ) ( cz fs )`, `( two ( string_data s ) 1 )`, `( two ( string_data t ) ( cz fs ) )` over another String, `( two ( string_data t ) ( string_len s ) )`, and a join whose condition only reads fs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ two s a i b → i { ^ + ( nurl_str_len a ) b }

@ id s a → s { ^ a }

@ mkfs → ( Vec String ) { : ( Vec String ) fs ( vec_new [String] ) ( vec_push [String] fs ( string_from `a heap string long enough to own a buffer` ) ) ( vec_push [String] fs ( string_from `another heap string long enough to own one` ) ) ^ fs }

@ main → i {
    : ( Vec String ) fs ( mkfs )
    : String s ( vec_at [String] fs 1 )
    : String t ( string_from `a third heap string long enough to own one` )
    ( nurl_println_int ( two ( string_data s ) 1 ) )
    ( nurl_println_int ( two ( string_data t ) ( string_len s ) ) )
    : s v ( string_data s )
    : s w ? == 0 ( vec_len [String] fs ) `` v
    ( nurl_println w )
    ( nurl_println_int ( two ( string_data t ) ( cz fs ) ) )
    : ( Vec String ) gs ( mkfs )
    : String u ( vec_at [String] gs 0 )
    ( nurl_println_int + ( string_len u ) ( cz gs ) )
    ^ 0
}
