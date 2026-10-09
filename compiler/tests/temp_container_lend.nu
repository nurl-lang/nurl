// temp_container_lend.nu — an element borrowed out of a temporary
// container (a call's fresh result handed straight to `vec_get`) is the
// caller's own copy, and the temporary is dropped after the call.
//
// `vec_get` reads its element through the Vec's buffer: the raw-provenance
// summary said the Vec was "lent back" — and lent back WHOLE, as if the
// result were the Vec itself. The caller then took the temporary for moved
// into the result: it never dropped it, and the element's String was
// freed through the result while the Vec's block leaked (tools/fuzz/holes
// h96). A value read through a parameter is PART of it: the result is
// copied when the callee lent it, and the temporary goes right after the
// call. Every shape below runs LSan-clean (run_san_tests.sh): bound, a
// match scrutinee, in a loop, handed back, passed on, a user generic, a
// callee lending from a temporary or a named argument, a Vec of Vecs.
// A named container stays the owner: its elements are borrowed, not
// copied.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ mk → ( Vec String ) {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long string element on the heap` ) )
    ( vec_push [String] v ( string_from `a second long string element on the heap` ) )
    ^ v
}

@ second → ?String { ^ ( vec_get [String] ( mk ) 1 ) }

@ olen ? String o → i { ?? o { T e → { ^ ( string_len e ) } F → { ^ 0 } } }

@ first [A] ( Vec A ) v → ?A { ^ ( vec_get [A] v 0 ) }

@ pick ( Vec String ) a ( Vec String ) b i k → ?String {
    ? == k 0 { ^ ( vec_get [String] a 0 ) } {}
    ^ ( vec_get [String] b 1 )
}

@ mkv → ( Vec ( Vec i ) ) {
    : ( Vec ( Vec i ) ) v ( vec_new [( Vec i )] )
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 7 )
    ( vec_push [i] a 8 )
    ( vec_push [( Vec i )] v a )
    ^ v
}

@ main → i {
    // Bound, then matched.
    : ?String o ( vec_get [String] ( mk ) 0 )
    ?? o { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    // The scrutinee itself.
    ?? ( vec_get [String] ( mk ) 1 ) { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    // Once per iteration.
    : ~ i n 0
    : ~ i k 0
    ~ < k 50 {
        ?? ( vec_get [String] ( mk ) 1 ) { T e → { = n + n ( string_len e ) } F → {} }
        = k + k 1
    }
    ( nurl_println_int n )
    // Handed back by a function; passed straight on.
    ?? ( second ) { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    ( nurl_println_int ( olen ( vec_get [String] ( mk ) 0 ) ) )
    // A user generic lending part of its argument.
    : ?String g ( first [String] ( mk ) )
    ?? g { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    // A callee lending from the temporary or from a named argument.
    : ( Vec String ) named ( mk )
    : ?String p ( pick ( mk ) named 1 )
    ?? p { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    : ?String q ( pick ( mk ) named 0 )
    ?? q { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    // A named container keeps its elements.
    ?? ( vec_get [String] named 0 ) { T e → { ( nurl_println_int ( string_len e ) ) } F → {} }
    ( nurl_println_int ( vec_len [String] named ) )
    // A Vec read out of a temporary Vec of Vecs.
    ?? ( vec_get [( Vec i )] ( mkv ) 0 ) { T e → { ( nurl_println_int ( vec_len [i] e ) ) } F → {} }
    ^ 0
}
