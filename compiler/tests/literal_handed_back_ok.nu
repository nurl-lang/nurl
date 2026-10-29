// literal_handed_back_ok.nu — an aggregate literal handed straight to a
// callee that hands it back (agora #171): whole (`^ p`), in part
// (`^ . p s`), rewrapped, through a generic and through a callee defined
// further down. The result owns what it holds; each String is freed
// once — AddressSanitizer- and LeakSanitizer-clean.

$ `stdlib/core/string.nu`

: P { String s i n }

@ pass P p → P { ^ p }

@ name P p → String { ^ . p s }

@ id [T] T x → T { ^ x }

@ wrap ? String o → ?String {
    ?? o {
        T s → { ^ @ ?String { T s } }
        F → { ^ @ ?String { F } }
    }
}

@ main → i {
    : P a ( pass @ P { ( string_from `whole` ) 1 } )
    ( nurl_println ( string_data . a s ) )
    : String b ( name @ P { ( string_from `in part` ) 2 } )
    ( nurl_println ( string_data b ) )
    : ?String c ( wrap @ ?String { T ( string_from `rewrapped` ) } )
    ?? c { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    : P d ( id [P] @ P { ( string_from `through a generic` ) 3 } )
    ( nurl_println ( string_data . d s ) )
    : P e ( later @ P { ( string_from `through a later callee` ) 4 } )
    ( nurl_println ( string_data . e s ) )
    ^ 0
}

@ later P p → P { ^ p }
