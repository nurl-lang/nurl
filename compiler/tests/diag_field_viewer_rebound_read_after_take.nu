// `: R b a` over a field viewer views the same field: once `b` takes the
// field over, `a` is a copy of a handle `b`'s consumer owns — reading it
// after is rejected (agora #271).
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ eat sink R r → i { ^ ( vec_len [i] . r v ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : C col @ C { @ R { xs } 0 }
    : R a . col res
    : R b a
    ? > ( vec_len [i] . a v ) 0 { ( nurl_println_int ( eat b ) ) } {}
    ^ ( vec_len [i] . a v )
}
