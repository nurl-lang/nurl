// borrow_read_in_a_join_arm_after_the_conditions_call_cleared_its_source: agora #577 — `? == 0 ( cz fs ) ( string_len s ) 0`, s a borrow of fs's element, cz clearing fs
// Closed: a call reads its argument where it runs; one that another call of the statement ended first — an earlier call, or a call nested in this one — is read after its end (agora #577).
// main ee38fbb: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #577: `? == 0 ( cz fs ) ( string_len s ) 0`, s a borrow of fs's element, cz clearing fs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a first string long enough for a heap buffer` ) )
    ( vec_push [String] fs ( string_from `a second string long enough for a heap buffer` ) )
    : String s ( vec_at [String] fs 1 )
    : i r ? == 0 ( cz fs ) ( string_len s ) 0
    ( nurl_println_int r )
    ^ 0
}
