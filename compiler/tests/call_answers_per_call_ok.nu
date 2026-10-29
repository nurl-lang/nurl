// call_answers_per_call_ok.nu — a callee that lends its argument on one
// path and hands over a fresh value on another answers per call whether
// its result is owned (agora #185). Whoever holds that result goes by the
// answer — a binding (a String, an option, a result, an enum, a struct),
// an argument's temporary, a discarded value, a store into a literal, a
// Vec or a field, a `sink` parameter, a join's arm, a match's scrutinee:
// the fresh value is dropped or moved in, the lent one is copied or left
// to its owner.
// Runs clean under the sanitizers.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick_str String p b c → String { ^ ? c p ( mk ) }

@ pick_opt String p b c → ?String { ^ @ ?String { T ? c p ( mk ) } }

@ eat sink String s → i { ^ ( string_len s ) }

@ pick_res String p b c → !String i { ^ @ !String i { T ? c p ( mk ) } }

@ pick_enum E e b c → E { ^ ? c e @ E { S ( mk ) } }

: P { String s i n }

@ pick_struct P p b c → P { ^ ? c p @ P { ( mk ) 2 } }

@ main → i {
    : String p ( mk )
    : E g @ E { S ( mk ) }
    : P q @ P { ( mk ) 1 }
    : ( Vec String ) keep ( vec_new [String] )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        : b c > k 4
        : String a ( pick_str p c )
        : ?String o ( pick_opt p c )
        : !String i r ( pick_res p c )
        : E e ( pick_enum g c )
        = acc + acc ( string_len a )
        = acc + acc ?? o { T s → ( string_len s ) F → 0 }
        = acc + acc ?? r { T s → ( string_len s ) F x → x }
        = acc + acc ?? e { S s → ( string_len s ) NoVal → 0 }
        : P w ( pick_struct q c )
        = acc + acc ( string_len . w s )
        = acc + acc ( string_len ( pick_str p c ) )
        ( pick_str p c )
        ? c { ( pick_str p c ) } {}
        : P lit @ P { ( pick_str p c ) 3 }
        = acc + acc ( string_len . lit s )
        : ~ P st @ P { ( mk ) 4 }
        = . st s ( pick_str p c )
        = acc + acc ( string_len . st s )
        ( vec_push [String] keep ( pick_str p c ) )
        = acc + acc ( eat ( pick_str p c ) )
        : String j ? > k 1 ( pick_str p c ) ( mk )
        = acc + acc ( string_len j )
        = acc + acc ?? ( pick_opt p c ) { T s → ( string_len s ) F → 0 }
        : String h ?? ( pick_opt p c ) { T s → s F → ( mk ) }
        = acc + acc ( string_len h )
        = k + k 1
    }
    ( nurl_println_int + + acc ( string_len p ) ( vec_len [String] keep ) )
    ^ 0
}
