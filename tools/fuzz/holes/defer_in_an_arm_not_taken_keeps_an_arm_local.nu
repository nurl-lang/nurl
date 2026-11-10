// defer_in_an_arm_not_taken_keeps_an_arm_local: `? c { : String g … ; { … g … } } {}`, the arm not taken.
// Closed: the arm's `g` is kept back by the arm's defer and released by fn_cleanup, which the path around the arm runs too: under its "left to the cleanup" flag, set at the arm's end (mem_dkeep_mark, agora #630). Its own drop flag is no answer there: it is written by the binding, which did not run.
// main d96ebfa: accepted; the cleanup reads an uninitialised drop flag and releases storage the binding never filled (UndefinedBehaviorSanitizer: misaligned load; SEGV).
// map: §7.1 | A2 | runs-clean | - | agora #630: a `;` defer in an arm that is not taken keeps an arm-local owner — the cleanup released storage the binding never filled
$ `stdlib/core/string.nu`

@ f i n → i {
    ? > n 1 { : String g ( string_from `g: a string long enough for a heap buffer, yes` ) ; { ( nurl_println_int ( string_len g ) ) } } {}
    ^ n
}

@ main → i {
    ( nurl_println_int ( f 1 ) )
    ( nurl_println_int ( f 2 ) )
    ^ 0
}
