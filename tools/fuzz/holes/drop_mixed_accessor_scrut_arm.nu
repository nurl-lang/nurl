// drop_mixed_accessor_scrut_arm: agora #203 — `?? ( pick T r )`, pick = `? c { ^ q } {}  ^ @ ?Res { T ( mkres ) }`: the arm dropped r's payload (drop_mixed_accessor_scrut_arm).
// Closed: `^ p` of a parameter that cannot be copied (__nc_held_ty) records retlend and hands back the parameter's flag as the per-call ownership bit, as for a String / Vec: a function that hands it back on one path and a fresh value on another answers per call (agora #203).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h951 | a `??` over a call handing back its option parameter or a fresh one: the arm dropped r's payload
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

@ pick b c ? Res q → ?Res {
    ? c { ^ q } {}
    ^ @ ?Res { T ( mkres ) }
}

@ main → i {
    : ?Res r @ ?Res { T ( mkres ) }
    ?? ( pick T r ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ?? ( pick F r ) { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ?? r { T e → ( nurl_println_int ( vec_len [i] . e buf ) ) F → ( nurl_println `none` ) }
    ^ 0
}
