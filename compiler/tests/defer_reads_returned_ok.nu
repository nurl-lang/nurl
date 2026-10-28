// defer_reads_returned_ok.nu — a `;` defer and the value a return hands
// back (agora #165). The defers run after the value is the caller's: they
// may read it, and a defer the path to a return never armed (one in an arm
// that returned on its own, one registered after an early return) does
// not run there at all.

$ `stdlib/core/string.nu`

@ mk s t → String { ^ ( string_from t ) }

@ logged → String {
    : String s ( mk `logged` )
    ; { ( nurl_println ( string_data s ) ) }
    ^ s
}

@ arm_returns b c → String {
    : String s ( mk `kept` )
    ? c { ; { ( string_free s ) } ^ ( mk `fresh` ) } {}
    ^ s
}

@ early b c → String {
    : String s ( mk `early` )
    ? c { ^ s } {}
    ; { ( string_free s ) }
    ^ ( mk `late` )
}

@ main → i {
    : String a ( logged )
    ( nurl_println ( string_data a ) )
    : String b ( arm_returns F )
    ( nurl_println ( string_data b ) )
    : String c ( arm_returns T )
    ( nurl_println ( string_data c ) )
    : String d ( early T )
    ( nurl_println ( string_data d ) )
    : String e ( early F )
    ( nurl_println ( string_data e ) )
    ^ 0
}
