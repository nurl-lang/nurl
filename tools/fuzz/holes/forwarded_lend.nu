// forwarded_lend: a function returning another function's lent result over its own parameter (`@ fwd Tp tp i id → Tz { ^ ( getv tp id ) }`, getv handing back a view of tp's elements) did not lend that parameter itself when getv was compiled first: only a callee compiled AFTER the caller had its lend carried over (resolve_retfwd_lends). The caller's binding of fwd's result was nobody's view, so truncating tp left it reading freed elements (onnx's per-op `__in`, an inout accessor over `rt_at`).
// Closed: every `^ ( g … )` notes which of the caller's parameters sit at g's argument positions (a field path's root included), and the module-end fixpoint lends each one g lends.
// main's compiler: `t` is read after `cut` freed what it points into.
// map: CallT.summary | A1 | rejected | h271 | function forwards another fn's lent result; its own lend not summarised
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Tz { ( Vec f ) data }
: Tp { ( Vec Tz ) vals }

@ tz_empty → Tz { ^ @ Tz { ( vec_new [f] ) } }

@ getv Tp tp i id → Tz { ^ ?? ( vec_get [Tz] . tp vals id ) { T x → x F → ( tz_empty ) } }

@ fwd inout Tp tp i id → Tz { ^ ( getv tp id ) }

@ cut inout Tp tp → v { : b _t ( vec_truncate [Tz] . tp vals 0 ) }

@ work inout Tp tp → v {
    : Tz t ( fwd tp 0 )
    ( cut tp )
    ( nurl_println_int ( vec_len [f] . t data ) )
}

@ main → i {
    : ~ Tp tp @ Tp { ( vec_new [Tz] ) }
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d 1.5 )
    ( vec_push [Tz] . tp vals @ Tz { d } )
    ( work tp )
    ^ 0
}
