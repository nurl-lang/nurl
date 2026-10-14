// A closure's fall-off value is its caller's own, as `^` hands it (h217):
// what the body only lent — a call that lent, a capture by name, a field
// of one, a binding that owns nothing — comes back a copy; what the body
// owns leaves with the return.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bx { ( Vec i ) items i n }

@ mkbx → Bx {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 2 )
    ^ @ Bx { v 1 }
}

@ apply [T] ( @ T ) f → T { ^ ( f ) }

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    : ( Vec ( Vec i ) ) outer ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] outer seed )
    // A call that lent.
    : ( @ ( Vec i ) ) elem \ → ( Vec i ) { ( vec_at [( Vec i )] outer 0 ) }
    ( vec_push [i] ( elem ) 1 )
    // A capture by name, twice.
    : ( Vec i ) kept ( vec_new [i] )
    ( vec_push [i] kept 7 )
    : ( @ ( Vec i ) ) cap \ → ( Vec i ) { kept }
    ( vec_push [i] ( cap ) 1 )
    ( vec_push [i] ( cap ) 1 )
    // A field of a capture, and a whole captured struct.
    : ( Vec i ) s2 ( vec_new [i] )
    ( vec_push [i] s2 3 )
    : Bx b @ Bx { s2 1 }
    : ( @ ( Vec i ) ) fld \ → ( Vec i ) { . b items }
    ( vec_push [i] ( fld ) 1 )
    : ( @ Bx ) whole \ → Bx { b }
    : Bx w ( whole )
    ( vec_push [i] . w items 1 )
    // A binding that aliases an element, and one bound to a join.
    : b c == 1 1
    : ( @ ( Vec i ) ) al \ → ( Vec i ) { : ( Vec i ) e ( vec_at [( Vec i )] outer 0 ) e }
    ( vec_push [i] ( al ) 1 )
    : ( @ ( Vec i ) ) jn \ → ( Vec i ) { : ( Vec i ) e ? c { ( vec_at [( Vec i )] outer 0 ) } { ( vec_new [i] ) } e }
    ( vec_push [i] ( jn ) 1 )
    // A struct the body made: its field is copied, the struct dropped.
    : ( @ ( Vec i ) ) lf \ → ( Vec i ) { : ( Vec i ) t ( vec_new [i] ) ( vec_push [i] t 4 ) : Bx l @ Bx { t 1 } . l items }
    : ( Vec i ) r1 ( lf )
    ( vec_push [i] r1 1 )
    // A field of a call that handed the whole over leaves with it.
    : ( @ ( Vec i ) ) tf \ → ( Vec i ) { . ( mkbx ) items }
    : ( Vec i ) r2 ( tf )
    ( vec_push [i] r2 1 )
    // What the body owns leaves with the return.
    : ( @ ( Vec i ) ) own \ → ( Vec i ) { : ( Vec i ) t ( vec_new [i] ) ( vec_push [i] t 9 ) t }
    : ( Vec i ) r3 ( own )
    ( vec_push [i] r3 1 )
    // Through a generic instance and a closure-returning closure.
    : ( Vec i ) r4 ( apply [( Vec i )] \ → ( Vec i ) { ( vec_at [( Vec i )] outer 0 ) } )
    ( vec_push [i] r4 1 )
    : ( @ ( @ ( Vec i ) ) ) mk \ → ( @ ( Vec i ) ) { \ → ( Vec i ) { kept } }
    : ( @ ( Vec i ) ) g ( mk )
    ( vec_push [i] ( g ) 1 )
    // A String capture.
    : String name ( string_from `ann` )
    : ( @ String ) nm \ → String { name }
    : String n1 ( nm )
    ( string_push_str n1 `!` )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] outer 0 ) ) )
    ( nurl_println_int ( vec_len [i] kept ) )
    ( nurl_println_int ( vec_len [i] . b items ) )
    ( nurl_println_int ( vec_len [i] r1 ) )
    ( nurl_println_int ( vec_len [i] r2 ) )
    ( nurl_println_int ( vec_len [i] r3 ) )
    ( nurl_println_int ( vec_len [i] r4 ) )
    ( nurl_println ( string_data name ) )
    ( nurl_println ( string_data n1 ) )
    ^ 0
}
