// should_fail_forwarded_lend.nu — h271.
//
// `fwd` returns `getv`'s result over its own parameter, and getv lends
// it (a `vec_get` payload of its field). getv compiles first, and fwd
// still lends tp: the caller's binding is a view of tp, so emptying tp
// before reading it is rejected.
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Tz { ( Vec f ) data }
: Tp { ( Vec Tz ) vals }

@ tz_empty → Tz { ^ @ Tz { ( vec_new [f] ) } }

@ getv Tp tp i id → Tz { ^ ?? ( vec_get [Tz] . tp vals id ) { T x → x F → ( tz_empty ) } }

@ fwd Tp tp i id → Tz { ^ ( getv tp id ) }

@ cut Tp tp → v { : b _t ( vec_truncate [Tz] . tp vals 0 ) }

@ main → i {
    : Tp tp @ Tp { ( vec_new [Tz] ) }
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d 1.5 )
    ( vec_push [Tz] . tp vals @ Tz { d } )
    : Tz t ( fwd tp 0 )
    ( cut tp )
    ( nurl_println_int ( vec_len [f] . t data ) )
    ^ 0
}
