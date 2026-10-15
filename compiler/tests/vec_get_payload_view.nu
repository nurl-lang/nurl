// vec_get_payload_view.nu — h270's allowed shapes.
//
// An accessor handing back a `vec_get` payload of its parameter's field
// lends that parameter: a view read before the argument changes, and a
// copy kept across the change, are both fine.
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Tz { ( Vec f ) data }
: Tp { ( Vec Tz ) vals }

@ tz_empty → Tz { ^ @ Tz { ( vec_new [f] ) } }

@ getv Tp tp i id → Tz { ^ ?? ( vec_get [Tz] . tp vals id ) { T x → x F → ( tz_empty ) } }

@ datav Tp tp i id → ( Vec f ) {
    ^ ?? ( vec_get [Tz] . tp vals id ) { T x → . x data F → ( vec_new [f] ) }
}

@ cut Tp tp → v { : b _t ( vec_truncate [Tz] . tp vals 0 ) }

@ main → i {
    : Tp tp @ Tp { ( vec_new [Tz] ) }
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d 1.5 )
    ( vec_push [f] d 2.5 )
    ( vec_push [Tz] . tp vals @ Tz { d } )
    : Tz t ( getv tp 0 )
    ( nurl_println_int ( vec_len [f] . t data ) )
    : ( Vec f ) kept ( vec_clone [f] ( datav tp 0 ) )
    ( cut tp )
    ( nurl_println_int ( vec_len [f] kept ) )
    ( nurl_println_int ( vec_len [f] ( datav tp 0 ) ) )
    ( nurl_println_int ( vec_len [f] . ( getv tp 3 ) data ) )
    ^ 0
}
