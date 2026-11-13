// A binding bound from a field viewer — `: R b a` with `a` read out of
// `col.res` — views that same field: handed to a parameter that takes it,
// it takes the field over, as `( eat a )` would (agora #271). Its own
// reads beside `a`'s, before, are fine; so is a chain of them.
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ eat sink R r → i { ^ ( vec_len [i] . r v ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    ( vec_push [i] xs 1 )
    : C col @ C { @ R { xs } 0 }
    : R a . col res
    : R b a
    : R c b
    ( nurl_println_int ( vec_len [i] . a v ) )
    ( nurl_println_int ( vec_len [i] . b v ) )
    ( nurl_println_int ( eat c ) )
    // The field, taken over, is left empty where it lives.
    ( nurl_println_int ( vec_len [i] . . col res v ) )
    ^ 0
}
