// defer_in_an_arm_not_taken.nu — a `;` defer inside an arm binds a Vec
// and a String of its own (agora #432). When the arm is not taken the
// defer is never armed and its body never runs, but fn_cleanup reclaims
// what the body would have bound: it does so by each owner's drop flag,
// cleared at entry, so the slots the body never filled are left alone.
// Taken, the body runs and its owners are released after the chain.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ fill b c i k → i {
    ? c { ; { : ( Vec i ) g ( vec_new [i] ) ( vec_push [i] g 7 ) ( nurl_println_int ( vec_len [i] g ) ) } } {}
    ? c { ; { : String s ( string_from `a string that lives in an arm's defer, long enough` ) ( nurl_println ( string_data s ) ) } } {}
    ^ k
}

@ main → i {
    ( nurl_println_int ( fill F 2 ) )
    ( nurl_println_int ( fill T 3 ) )
    ^ 0
}
