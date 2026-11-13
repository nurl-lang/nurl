// A binding read out of a field of a field (`. . col res v`) and one read
// out of the field holding it (`. col res`): consuming the outer one takes
// the inner field with it, so reading the inner viewer after is rejected
// (agora #271; a use-after-free on main before it).
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ eat sink R r → i { ^ ( vec_len [i] . r v ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C col @ C { @ R { xs } 0 }
    : ( Vec i ) w . . col res v
    : R a . col res
    ( nurl_println_int ( eat a ) )
    ^ ( vec_len [i] w )
}
