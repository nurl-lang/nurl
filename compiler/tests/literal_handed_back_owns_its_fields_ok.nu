// literal_handed_back_owns_its_fields_ok.nu — a literal built as an
// argument and handed back by its callee (agora #172, #173): the result
// owns a binding's value and a fresh one alike, and a closure binding's
// env copy is the literal's to drop whatever the callee does with it.
// Runs clean under the sanitizers: no double free, no leak.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: V2 { ( Vec String ) xs String s }

: H { ( @ i ) cb i pad }

@ pass V2 v → V2 { ^ v }

@ id [T] T v → T { ^ v }

@ pick V2 v → String { ^ . v s }

@ unwrap ? ( @ i ) o → ( @ i ) { ^ ?? o { T g → g F → \ → i { ^ 0 } } }

@ cb_of H h → ( @ i ) { ^ . h cb }

@ call H h → i {
    : ( @ i ) c . h cb
    ^ ( c )
}

@ main → i {
    : ( Vec String ) b ( vec_new [String] )
    ( vec_push [String] b ( mk ) )
    : V2 r ( pass @ V2 { b ( mk ) } )
    ( nurl_println_int + ( vec_len [String] . r xs ) ( string_len . r s ) )
    : ( Vec String ) b2 ( vec_new [String] )
    : V2 g ( id [V2] @ V2 { b2 ( mk ) } )
    ( nurl_println_int ( string_len . g s ) )
    : ( Vec String ) b3 ( vec_new [String] )
    : String p ( pick @ V2 { b3 ( mk ) } )
    ( nurl_println_int ( string_len p ) )
    : ~ i x 40
    : ( @ i ) f \ → i { = x + x 1 ^ x }
    : ( @ i ) u ( unwrap @ ?( @ i ) { T f } )
    : ( @ i ) k ( cb_of @ H { f 0 } )
    ( nurl_println_int + + ( u ) ( k ) ( call @ H { f 1 } ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
