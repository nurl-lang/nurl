// closure_uncopyable_capture_ok.nu — what agora #161's rule leaves alone:
// a closure over a ( Vec D ) (no Clone) that stays in its frame — run
// there, kept in a local struct or a local Vec — and the cure the
// diagnostic names: share the value as an ( Rc T ), whose handle the
// adopted closure copies. A ( Vec String ) has a Clone: adopting copies it
// in, so that closure may leave (diag_closure_uncopyable_capture_escapes).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string that owns a heap buffer` ) n } }

: H { ( @ i ) cb i pad }

@ local_uses → i {
    : ( Vec D ) v ( vec_new [D] )
    ( vec_push [D] v ( mkd 1 ) )
    : ( @ i ) f \ → i { ^ ( vec_len [D] v ) }
    : H h @ H { f 0 }
    : ( Vec ( @ i ) ) fs ( vec_new [( @ i )] )
    ( vec_push [( @ i )] fs f )
    : ( @ i ) hc . h cb
    : ~ i n ( hc )
    ?? ( vec_get [( @ i )] fs 0 ) { T g → { = n + n ( g ) } F _ → {} }
    ^ n
}

@ shared → H {
    : ( Vec D ) v0 ( vec_new [D] )
    ( vec_push [D] v0 ( mkd 2 ) )
    ( vec_push [D] v0 ( mkd 3 ) )
    : ( Rc ( Vec D ) ) v ( rc_new [( Vec D )] v0 )
    : ( @ i ) f \ → i { ^ ( vec_len [D] ( rc_get [( Vec D )] v ) ) }
    ^ @ H { f 0 }
}

@ shared_into ( Vec ( @ i ) ) out → v {
    : ( Vec D ) v0 ( vec_new [D] )
    ( vec_push [D] v0 ( mkd 4 ) )
    : ( Rc ( Vec D ) ) v ( rc_new [( Vec D )] v0 )
    : ( @ i ) f \ → i { ^ ( vec_len [D] ( rc_get [( Vec D )] v ) ) }
    ( vec_push [( @ i )] out f )
}

@ copied → H {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `copied in` ) )
    : ( @ i ) f \ → i { ^ ( vec_len [String] v ) }
    ^ @ H { f 0 }
}

@ main → i {
    ( nurl_println_int ( local_uses ) )
    : H a ( shared )
    : ( @ i ) ac . a cb
    ( nurl_println_int ( ac ) )
    : ( Vec ( @ i ) ) o ( vec_new [( @ i )] )
    ( shared_into o )
    ?? ( vec_get [( @ i )] o 0 ) { T g → { ( nurl_println_int ( g ) ) } F _ → {} }
    : H c ( copied )
    : ( @ i ) cc . c cb
    ( nurl_println_int ( cc ) )
    ^ 0
}
