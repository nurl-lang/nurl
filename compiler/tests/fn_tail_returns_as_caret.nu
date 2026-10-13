// A function body's final value — a name, a call or a field read — returns
// as `^` returns it (h218): a parameter, an element or a field of one, a
// binding that aliases one, all handed back as lends the caller does not
// release; a field of a struct the body made comes back the caller's own.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bx { ( Vec i ) items i n }

@ idv ( Vec i ) v → ( Vec i ) { v }

@ first ( Vec ( Vec i ) ) xs → ( Vec i ) { ( vec_at [( Vec i )] xs 0 ) }

@ first_alias ( Vec ( Vec i ) ) xs → ( Vec i ) { : ( Vec i ) e ( vec_at [( Vec i )] xs 0 ) e }

@ items_of Bx b → ( Vec i ) { . b items }

@ first_items ( Vec Bx ) bxs → ( Vec i ) { . ( vec_at [Bx] bxs 0 ) items }

@ made → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s 4 )
    : Bx l @ Bx { s 1 }
    . l items
}

@ name0 ( Vec String ) xs → String { ( vec_at [String] xs 0 ) }

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    ( vec_push [i] seed 5 )
    ( vec_push [i] ( idv seed ) 1 )
    : ( Vec ( Vec i ) ) outer ( vec_new [( Vec i )] )
    : ( Vec i ) s1 ( vec_new [i] )
    ( vec_push [i] s1 5 )
    ( vec_push [( Vec i )] outer s1 )
    ( vec_push [i] ( first outer ) 1 )
    ( vec_push [i] ( first_alias outer ) 1 )
    : ( Vec i ) s2 ( vec_new [i] )
    ( vec_push [i] s2 3 )
    : Bx bb @ Bx { s2 1 }
    ( vec_push [i] ( items_of bb ) 1 )
    : ( Vec Bx ) bxs ( vec_new [Bx] )
    : ( Vec i ) s3 ( vec_new [i] )
    ( vec_push [i] s3 8 )
    ( vec_push [Bx] bxs @ Bx { s3 1 } )
    ( vec_push [i] ( first_items bxs ) 1 )
    : ( Vec i ) m ( made )
    ( vec_push [i] m 1 )
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `abc` ) )
    ( nurl_println_int ( vec_len [i] seed ) )
    ( nurl_println_int ( vec_len [i] ( vec_at [( Vec i )] outer 0 ) ) )
    ( nurl_println_int ( vec_len [i] . bb items ) )
    ( nurl_println_int ( vec_len [i] . ( vec_at [Bx] bxs 0 ) items ) )
    ( nurl_println_int ( vec_len [i] m ) )
    ( nurl_println ( string_data ( name0 names ) ) )
    ^ 0
}
