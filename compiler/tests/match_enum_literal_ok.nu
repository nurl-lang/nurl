// match_enum_literal_ok.nu — a `??` over an enum literal (agora #182).
// The literal has an owner of its own, as a call's result has: dropped
// at the end of its scope (every round, in a loop), its payload taken out
// by an arm that hands it on, a binding's value moved into it.
// Runs clean under the sanitizers.

$ `stdlib/core/string.nu`

: P { String s i n }

: | E {
    S String
    V P
    NoVal
}

: | Fz {
    In E
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part i k → String { ^ ?? @ E { V @ P { ( mk ) k } } { S x → x V p → . p s NoVal → ( mk ) } }

@ main → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        ?? @ E { S ( mk ) } { S x → { = acc + acc ( string_len x ) } V p → {} NoVal → {} }
        ?? @ E { V @ P { ( mk ) k } } { S x → {} V p → { = acc + acc . p n } NoVal → {} }
        : String t ?? @ E { S ( mk ) } { S x → x V p → ( mk ) NoVal → ( mk ) }
        = acc + acc ( string_len t )
        = acc + acc ( string_len ( part k ) )
        ?? @ Fz { In @ E { S ( mk ) } } { In e → { ?? e { S x → { = acc + acc ( string_len x ) } V p → {} NoVal → {} } } Nil → {} }
        : String b ( mk )
        ?? @ E { S b } { S x → { = acc + acc ( string_len x ) } V p → {} NoVal → {} }
        = k + k 1
    }
    ( nurl_println_int acc )
    ^ 0
}
