// What a `sink` or a keeping callee may be handed from a lending call
// (h228, h230): a String it lends comes over as a copy, so the Vec keeps
// its own; a value a call hands over goes as is; and a `% Drop` element
// is taken out of its Vec (vec_pop) before it is handed on.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

@ consume sink String s → v {
    ( nurl_println ( string_data s ) )
}

@ eat sink Res r → v {
}

@ firsts ( Vec String ) v → String {
    ^ ( vec_at [String] v 0 )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `abc` ) )
    ( consume ( vec_at [String] v 0 ) )
    ( consume ( firsts v ) )
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    : ( Vec Res ) rs ( vec_new [Res] )
    ( vec_push [Res] rs @ Res { ( vec_new [i] ) } )
    ( eat @ Res { ( vec_new [i] ) } )
    ?? ( vec_pop [Res] rs ) { T r → { ( eat r ) } F _ → {} }
    ( nurl_println_int ( vec_len [Res] rs ) )
    ^ 0
}
