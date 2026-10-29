// join_field_lend_ok.nu — a `?` / `??` arm that hands out a field (agora
// #178):
// - of a parameter, or of a payload binding or cursor over one: that
//   parameter is lent back in part, so a literal argument goes with the
//   result and a binding argument stays its own;
// - of a value this function releases (a local, a `sink` parameter, a
//   payload of one, a match's temporary): copied at the return.
// Runs clean under the sanitizers.

$ `stdlib/core/string.nu`

: P { String s i n }

: | G {
    V P
    Nil
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ mkg i n → G { ^ @ G { V @ P { ( mk ) n } } }

@ part P p b c → String { ^ ? c . p s ( mk ) }

@ payload G g → String { ^ ?? g { V p → . p s Nil → ( mk ) } }

@ in_arm G g b c → String { ^ ?? g { V p → ? c ( mk ) . p s Nil → ( mk ) } }

@ block_arm G g → String { ^ ?? g { V p → { . p s } Nil → ( mk ) } }

@ opt ? P o → String { ^ ?? o { T p → . p s F → ( mk ) } }

@ local i n b c → String {
    : P p @ P { ( mk ) n }
    ^ ? c . p s ( mk )
}

@ sink_param sink P p b c → String { ^ ? c . p s ( mk ) }

@ local_enum i n → String {
    : G g ( mkg n )
    ^ ?? g { V p → . p s Nil → ( mk ) }
}

@ sink_enum sink G g → String { ^ ?? g { V p → . p s Nil → ( mk ) } }

@ temp_enum i n → String { ^ ?? ( mkg n ) { V p → . p s Nil → ( mk ) } }

@ main → i {
    : P p @ P { ( mk ) 1 }
    : String a ( part p T )
    : String b ( part @ P { ( mk ) 2 } T )
    ( nurl_println_int + + ( string_len a ) ( string_len b ) . p n )
    : G g ( mkg 3 )
    : String c ( payload g )
    : String d ( payload ( mkg 4 ) )
    : String e ( in_arm ( mkg 5 ) F )
    : String f ( block_arm g )
    ( nurl_println_int + + + ( string_len c ) ( string_len d ) ( string_len e ) ( string_len f ) )
    : String h ( opt @ ?P { T @ P { ( mk ) 6 } } )
    ( nurl_println_int ( string_len h ) )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 20 {
        = acc + acc ( string_len ( local k T ) )
        = acc + acc ( string_len ( sink_param @ P { ( mk ) k } T ) )
        = acc + acc ( string_len ( local_enum k ) )
        = acc + acc ( string_len ( sink_enum ( mkg k ) ) )
        = acc + acc ( string_len ( temp_enum k ) )
        = k + k 1
    }
    ( nurl_println_int acc )
    ( nurl_println ( string_data a ) )
    ^ 0
}
