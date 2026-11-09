// vec_maybe_lend_of_a_local_returned_in_an_option: agora #531 — a Vec a callee may hand back (`: ( Vec i ) x ( maybev o k )`), returned as `^ @ ?( Vec i ) { T x }`: on the runs it lent the local o, o's buffer left with the result by identity while the function answered "lent" — it leaked
// main: leaked (LSan with use_stacks=0:use_registers=0, or clang 23's default LSan).
// map: §7.2 | A2 | runs-clean | - | agora #531: a maybe-lend of a local Vec returned in an option answers owned by identity
$ `stdlib/core/vec.nu`

@ maybev ( Vec i ) a i k → ( Vec i ) { ? == k 0 { ^ a } {} : ( Vec i ) f ( vec_new [i] ) ( vec_push [i] f 7 ) ^ f }

@ run i k → ?( Vec i ) {
    : ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 1 ) ( vec_push [i] o 2 )
    : ( Vec i ) x ( maybev o k )
    ^ @ ?( Vec i ) { T x }
}

@ main → i {
    : ?( Vec i ) a ( run 0 )
    ?? a { T v → { ( nurl_println_int ( vec_len [i] v ) ) } F → {} }
    : ?( Vec i ) b ( run 1 )
    ?? b { T v → { ( nurl_println_int ( vec_len [i] v ) ) } F → {} }
    ^ 0
}
