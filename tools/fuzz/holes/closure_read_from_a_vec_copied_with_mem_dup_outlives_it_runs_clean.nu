// closure_read_from_a_vec_copied_with_mem_dup_outlives_it_runs_clean:
// `: g ( vec_at fs 1 )  : d ( mem_dup g )  ( vec_free fs )  ( d 10 )`. Since agora #552
// g is a lend of fs; the copy owns its env (no lend of fs, only what the closure
// captured), so it is accepted and runs on its own env. (On main before #552
// the first copy leaked.)
// map: §8.4 | A2 | runs-clean | - | a closure read out of a Vec, copied with mem_dup, called after the Vec is freed: the copy owns its env (agora #552).
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk i n → ( @ u64 u64 ) {
    : ~ String s ( string_new )
    : ~ i j 0
    ~ < j n { ( string_push_char s 97 ) = j + j 1 }
    ^ \ u64 x → u64 { ^ + x # u64 ( string_len s ) }
}

@ mkv i n → ( @ u64 u64 ) {
    : ( Vec u64 ) t ( vec_new [u64] )
    : ~ i j 0
    ~ < j n { ( vec_push [u64] t # u64 j ) = j + j 1 }
    ^ \ u64 x → u64 { ^ + x # u64 * 100 ( vec_len [u64] t ) }
}

@ fill → ( Vec ( @ u64 u64 ) ) {
    : ( Vec ( @ u64 u64 ) ) fs ( vec_new [( @ u64 u64 )] )
    ( vec_push [( @ u64 u64 )] fs ( mk 3 ) )
    ( vec_push [( @ u64 u64 )] fs ( mk 5 ) )
    ( vec_push [( @ u64 u64 )] fs ( mkv 4 ) )
    ^ fs
}

@ pr u64 x → v { ( nurl_println_int # i x ) }

@ main → i {
    : ( Vec ( @ u64 u64 ) ) fs ( fill )
    : ( @ u64 u64 ) g ( vec_at [( @ u64 u64 )] fs 1 )
    : ( @ u64 u64 ) d ( mem_dup g )
    ( vec_free [( @ u64 u64 )] fs )
    ( pr ( d 10 ) )
    ^ 0
}
