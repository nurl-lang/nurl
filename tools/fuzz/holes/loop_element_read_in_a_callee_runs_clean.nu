// loop_element_read_in_a_callee_runs_clean: agora #735 — a callee that only reads through its `~` loop element, beside a borrow of an element's String
// Control: a callee that only reads changes nothing of the parameter (agora #735).
// main 3a71bef7: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #735: a callee that only reads through its `~` loop element, beside a borrow of an element's String
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ ch ( Vec ( Vec String ) ) vs → i { : ~ i n 0 ~ x vs { = n + n ( vec_len [String] x ) } ^ n }

@ main → i {
    : ( Vec String ) a ( vec_new [String] )
    ( vec_push [String] a ( string_from `an element string long enough for a heap buffer` ) )
    : ( Vec ( Vec String ) ) vs ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vs a )
    : String e ( vec_at [String] ( vec_at [( Vec String )] vs 0 ) 0 )
    ( nurl_println_int ( ch vs ) )
    ( nurl_println ( string_data e ) )
    ^ 0
}
