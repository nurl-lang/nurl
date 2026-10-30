// try_nc_error_param: agora #205 — `: i v \ q`, q an `!i Res` parameter: the caller got q's error as its own and freed it twice (try_nc_error_param).
// Closed: a try whose failure cannot be copied hands it on as it is and tells the caller per call whether it owns it (mem_store_hown), recording what it is part of as `^ <operand>` would: a parameter or a field of one lent back, a join of parameters, a call's lends (mem_ret_lends_as_call); an `!T E` with an uncopyable E counts as uncopyable (__nc_wrap_payload) (agora #205).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h970 | agora #205: `\ q`, q a parameter whose error cannot be copied: the caller got its own argument's error as owned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mk i n → !i Res {
    ? > n 2 { ^ @ !i Res { T n } } {}
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ @ !i Res { F @ Res { v } }
}

@ f ! i Res q → !i Res {
    : String s ( string_from `a local string long enough for a heap buffer` )
    : i v \ q
    ^ @ !i Res { T + v ( string_len s ) }
}

@ main → i {
    : !i Res r ( mk 1 )
    ?? ( f r ) { T x → ( nurl_println_int x ) F e → ( nurl_println_int ( vec_len [i] . e buf ) ) }
    ?? r { T x → ( nurl_println_int x ) F e → ( nurl_println_int ( vec_len [i] . e buf ) ) }
    ^ 0
}
