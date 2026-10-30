// H950: agora #203 — `? c { ^ ( mkres ) } {}  ^ q`: the result was taken for a view of r, and the fresh value leaked (drop_param_ret_mixed_fresh_leak).
// Closed: `^ p` of a parameter that cannot be copied (__nc_held_ty) records retlend and hands back the parameter's flag as the per-call ownership bit, as for a String / Vec: a function that hands it back on one path and a fresh value on another answers per call (agora #203).
// main: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mkres → Res {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ @ Res { v }
}

@ f b c Res q → Res {
    ? c { ^ ( mkres ) } {}
    ^ q
}

@ main → i {
    : Res r ( mkres )
    : Res o ( f T r )
    : Res p ( f F r )
    ( nurl_println_int ( vec_len [i] . o buf ) )
    ( nurl_println_int ( vec_len [i] . p buf ) )
    ( nurl_println_int ( vec_len [i] . r buf ) )
    ^ 0
}
