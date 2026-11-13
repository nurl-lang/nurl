// Two bindings read out of one field: consuming one takes the field
// over (codegen empties it where it lives), so the other holds a copy of
// a handle the consumer now owns — reading it after is rejected, not a
// use-after-free (agora #271; accepted on main before it).
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ eat sink R r → i { ^ ( vec_len [i] . r v ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C col @ C { @ R { xs } 0 }
    : R a . col res
    : R b . col res
    ( nurl_println_int ( eat b ) )
    ^ ( vec_len [i] . a v )
}
