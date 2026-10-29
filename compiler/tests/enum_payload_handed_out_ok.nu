// enum_payload_handed_out_ok.nu — a payload handed out of an enum this
// function owns (a local, a `sink` parameter, a call's temporary) leaves it
// (agora #175): the enum's slot is zeroed and its drop skips it, a boxed
// one's box is freed. The rest of the enum is still dropped. One lent by a
// parameter the caller keeps stays a lend. Runs clean under the
// sanitizers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E {
    S String
    Pair String String
    NoVal
}

: P { String s i n }

: | B {
    V P
    NoB
}

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ first sink E e → String { ^ ?? e { S s → s Pair a b → a NoVal → ( mk ) } }

@ second sink E e → String {
    ?? e { S s → { ^ s } Pair a b → { ^ b } NoVal → {} }
    ^ ( mk )
}

@ lent E e → String { ^ ?? e { S s → s Pair a b → a NoVal → ( mk ) } }

@ make → E { ^ @ E { S ( mk ) } }

@ from_temp → String { ^ ?? ( make ) { S s → s Pair a b → b NoVal → ( mk ) } }

@ unbox sink B b → P { ^ ?? b { V p → p NoB → @ P { ( mk ) 0 } } }

@ pick sink E e b alt → String { ^ ?? e { S s → ? alt ( mk ) s Pair a b2 → a NoVal → ( mk ) } }

@ main → i {
    : String a ( first @ E { Pair ( mk ) ( mk ) } )
    : String b ( second @ E { Pair ( mk ) ( mk ) } )
    : String c ( second @ E { S ( mk ) } )
    : E kept @ E { S ( mk ) }
    : String d ( lent kept )
    : String e ( from_temp )
    : P p ( unbox @ B { V @ P { ( mk ) 7 } } )
    : String f ( pick @ E { S ( mk ) } T )
    : String g ( pick @ E { S ( mk ) } F )
    ( nurl_println_int + + + ( string_len a ) ( string_len b ) ( string_len c ) ( string_len d ) )
    ( nurl_println_int + + + ( string_len e ) . p n ( string_len f ) ( string_len g ) )
    : ( Vec String ) out ( vec_new [String] )
    : ~ i n 0
    ~ < n 6 {
        : ~ E x ? == 0 % n 2 @ E { S ( mk ) } @ E { Pair ( mk ) ( mk ) }
        : String t ?? x { S s → s Pair l r → r NoVal → ( mk ) }
        = x @ E { NoVal }
        ( vec_push [String] out t )
        = n + n 1
    }
    ( nurl_println_int ( vec_len [String] out ) )
    ?? kept { S s → { ( nurl_println_int ( string_len s ) ) } Pair l r → {} NoVal → {} }
    ^ 0
}
