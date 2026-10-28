// H415: as h408, in a generic function (`@ f [A] ?A o A d → A`) instantiated
// at `String`.
// Closed: as h408 (agora #146).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ f [A] ? A o A d → A { ^ ?? o { T s → s F → d } }

@ main → i {
    : ?String o @ ?String { T ( mk ) }
    : String s ( f [String] o ( mk ) )
    ( string_free s )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
    ^ 0
}
