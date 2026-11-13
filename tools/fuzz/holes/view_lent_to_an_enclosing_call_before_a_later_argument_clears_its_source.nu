// view_lent_to_an_enclosing_call_before_a_later_argument_clears_its_source: agora #604 — `( two ( string_data s ) ( cz fs ) )`, s a borrow of fs's element, cz clearing fs
// Closed: a value a call lends, handed to an enclosing call, is read where that call runs, after the calls in its later arguments; a join's value, after its condition's calls (agora #604).
// main 3cfdf8a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #604: `( two ( string_data s ) ( cz fs ) )`, s a borrow of fs's element, cz clearing fs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ two s a i b → i { ^ + ( nurl_str_len a ) b }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a heap string long enough to own a buffer` ) )
    ( vec_push [String] fs ( string_from `another heap string long enough to own one` ) )
    : String s ( vec_at [String] fs 1 )
    ( nurl_println_int ( two ( string_data s ) ( cz fs ) ) )
    ^ 0
}
