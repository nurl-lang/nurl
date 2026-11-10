// `^ ? c loc p` and `^ ?? k { … }` over a local and a parameter: the local
// is handed over, the parameter copied, a fresh value handed over — the
// caller owns the result on every path and the function releases the local
// on the paths that did not return it (agora #545, #540).
$ `stdlib/core/string.nu`

: | K { KA KB KC KD }

@ show [i a → v { ~ x a { ( nurl_println ( nurl_str_int x ) ) } }
@ mk → [i { ^ [i | 7 8] }

@ join b c [i p → [i {
    : [i loc [i | 1 2]
    ^ ? c loc p
}

@ join_s b c [String p → [String {
    : [String loc [String | ( string_from `a long enough string to be on the heap, loc` )]
    ^ ? c loc p
}

@ pick K k [i p → [i {
    : [i loc [i | 1 2 3]
    ^ ?? k { KA → loc KB → p KC → [i | 4] KD → ( mk ) }
}

@ early b c [i p → [i {
    ? c { ^ p } {}
    ^ [i | 1 2 3]
}

@ main → i {
    : [i q [i | 100 200]
    ( show ( join T q ) )
    ( show ( join F q ) )
    : [i r ( join F q )
    ( show r )
    ( show q )
    : [String qs [String | ( string_from `a long enough string to be on the heap, q` )]
    : [String r1 ( join_s F qs )
    ~ x r1 { ( nurl_println ( string_data x ) ) }
    : [String r2 ( join_s T qs )
    ~ x r2 { ( nurl_println ( string_data x ) ) }
    ~ x qs { ( nurl_println ( string_data x ) ) }
    ( show ( pick KA q ) )
    ( show ( pick KB q ) )
    ( show ( pick KC q ) )
    ( show ( pick KD q ) )
    ( show ( early T q ) )
    ( show ( early F q ) )
    ( show q )
    ^ 0
}
