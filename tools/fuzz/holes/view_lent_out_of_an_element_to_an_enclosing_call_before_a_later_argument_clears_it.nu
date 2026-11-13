// view_lent_out_of_an_element_to_an_enclosing_call_before_a_later_argument_clears_it: agora #604 — `( two ( string_data ( vec_at [String] fs 1 ) ) ( cz fs ) )`, no binding between
// Closed: a value a call lends, handed to an enclosing call, is read where that call runs, after the calls in its later arguments; a join's value, after its condition's calls (agora #604).
// main 3cfdf8a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #604: `( two ( string_data ( vec_at [String] fs 1 ) ) ( cz fs ) )`, no binding between
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
    ( nurl_println_int ( two ( string_data ( vec_at [String] fs 1 ) ) ( cz fs ) ) )
    ^ 0
}
