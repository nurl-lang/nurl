// enum_literal_argument_ok.nu — an enum literal built as a call's argument
// (agora #177):
// - dropped whole after a call that only borrows it, its payloads' boxes
//   with it;
// - its boxes freed when it holds a binding's value, which stays the
//   binding's;
// - kept by a keeper, consumed by a sink;
// - handed back whole, or a part of it handed back.
// Runs clean under the sanitizers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

: | E {
    Opt ? String
    S String
    Cb ( @ i )
    V P
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ show E e → i {
    ^ ?? e {
        Opt o → ?? o { T s → ( string_len s ) F → 0 }
        S s → ( string_len s )
        Cb f → ( f )
        V p → + ( string_len . p s ) . p n
        NoVal → -1
    }
}

@ pass E e → E { ^ e }

@ eat sink E e → i { ^ ( show e ) }

@ part E e → String { ^ ?? e { S s → s Opt o → ?? o { T s → s F → ( mk ) } Cb f → ( mk ) V p → ( mk ) NoVal → ( mk ) } }

@ main → i {
    : i v 41
    ( nurl_println_int + + ( show @ E { Opt @ ?String { T ( mk ) } } ) ( show @ E { S ( mk ) } ) ( show @ E { Cb \ → i { ^ + v 1 } } ) )
    ( nurl_println_int ( show @ E { V @ P { ( mk ) 1 } } ) )
    : String s ( mk )
    : ?String o @ ?String { T ( mk ) }
    ( nurl_println_int + ( show @ E { S s } ) ( show @ E { Opt o } ) )
    : E r ( pass @ E { Opt @ ?String { T ( mk ) } } )
    ( nurl_println_int + ( show r ) ( eat @ E { S ( mk ) } ) )
    : String t ( part @ E { S ( mk ) } )
    : String u ( part @ E { Opt @ ?String { T ( mk ) } } )
    ( nurl_println_int + ( string_len t ) ( string_len u ) )
    : ( Vec E ) xs ( vec_new [E] )
    ( vec_push [E] xs @ E { Opt @ ?String { T ( mk ) } } )
    : ~ i n 0
    : ~ i acc 0
    ~ < n 20 {
        = acc + acc ( show @ E { Opt @ ?String { T ( mk ) } } )
        = n + n 1
    }
    ( nurl_println_int + acc ( vec_len [E] xs ) )
    ( nurl_println ( string_data s ) )
    ^ 0
}
