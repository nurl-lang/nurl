// part_cursor_local_copied_ok.nu — a binding that a call lent part of a
// local into (`: String s ( gets w )`, or a try or a match over a call
// whose result holds `. w s`) is a cursor over part of w, not w's whole
// value: w goes on owning and dropping all of itself. Stored, pushed,
// assigned to an `inout` parameter or handed back in a literal, the part
// leaves as a copy; w's other fields are dropped with w (agora #195).

$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s String t i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

: H { String s }

@ gets W w → String { ^ . w s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw s t i n → W { ^ @ W { ( string_from t ) ( string_from `the rest` ) n } }

@ by_try → !String E {
    : W w ( mkw `a try's payload` 1 )
    : String s \ ( getr w )
    ^ @ !String E { T s }
}

@ by_match → !String E {
    : W w ( mkw `a match's payload` 2 )
    : String s ?? ( getr w ) { T x → x F _ → ( string_from `none` ) }
    ^ @ !String E { T s }
}

@ by_result → !String E {
    : W w ( mkw `a bound result` 3 )
    : !String E r ( getr w )
    ^ r
}

@ by_call_literal → !String E {
    : W w ( mkw `a call's lend in a literal` 4 )
    : String s ( gets w )
    ^ @ !String E { T s }
}

@ pushed ( Vec String ) v → v {
    : W w ( mkw `pushed` 5 )
    : String s ( gets w )
    ( vec_push [String] v s )
}

@ stored inout H h → v {
    : W w ( mkw `stored in a field` 6 )
    : String s ( gets w )
    = . h s s
}

@ assigned inout String o → v {
    : W w ( mkw `assigned to an inout` 7 )
    : String s ( gets w )
    = o s
}

@ show ! String E r → v {
    ?? r { T x → ( nurl_println ( string_data x ) ) F _ → ( nurl_println `bad` ) }
}

@ main → i {
    ( show ( by_try ) )
    ( show ( by_match ) )
    ( show ( by_result ) )
    ( show ( by_call_literal ) )
    : ( Vec String ) v ( vec_new [String] )
    ( pushed v )
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    : ~ H h @ H { ( string_from `old field` ) }
    ( stored h )
    ( nurl_println ( string_data . h s ) )
    : ~ String o ( string_from `old` )
    ( assigned o )
    ( nurl_println ( string_data o ) )
    ^ 0
}
