// payload_handed_back_by_another_name.nu — a `??` payload of an enum this
// function releases on the way out, handed back by a route other than
// `^ s` (Agora #783 B): bound to another name first (`: String t s ^ t`),
// as a join's value, through a generic identity (`^ ( gid [String] s )`),
// through a two-argument lender beside a parameter, an alias of an alias,
// out of an enum a call made (lent per call) and one a literal made (owned
// outright), a sink parameter's, a Vec payload. Each is the caller's own
// value: copied or taken out of the enum, never lent out of a local that
// dies on the way out. And (item 5) a literal handed back with a nested
// literal that lends whole beside a fresh field: the nested one is copied,
// so the result owns all it holds.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { EA String EB i }
: | V { VA ( Vec i ) VB i }

@ mke s t → E { ^ @ E { EA ( string_from t ) } }

@ gid [A] A x → A { ^ x }

@ pick String a String b i k → String { ^ ? == k 0 a b }

@ bound_first i k → String {
    : E e ( mke `a payload bound under another name, long enough` )
    ?? e { EA s → { : String t s ^ t } EB j → {} }
    ^ ( string_from `none` )
}

@ join_value i k → String {
    : E e ( mke `a payload as a join's value, long enough heap` )
    ^ ?? e { EA s → { : String t s t } EB j → ( string_from `none` ) }
}

@ through_gid i k → String {
    : E e ( mke `a payload through a generic identity, long` )
    ?? e { EA s → { ^ ( gid [String] s ) } EB j → {} }
    ^ ( string_from `none` )
}

@ through_pick String q i k → String {
    : E e ( mke `a payload beside a parameter, long enough heap` )
    ?? e { EA s → { ^ ( pick s q k ) } EB j → {} }
    ^ ( string_from `none` )
}

@ alias_of_alias i k → String {
    : E e ( mke `a payload under two other names, long enough` )
    ?? e { EA s → { : String t s : String u t ^ u } EB j → {} }
    ^ ( string_from `none` )
}

@ owned_outright i k → String {
    : E e @ E { EA ( string_from `a payload of a literal enum, long enough heap` ) }
    ?? e { EA s → { : String t s ^ t } EB j → {} }
    ^ ( string_from `none` )
}

@ of_a_sink sink E e → String {
    ?? e { EA s → { : String t s ^ t } EB j → {} }
    ^ ( string_from `none` )
}

@ mkv → V { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 4 ) ^ @ V { VA v } }

@ vec_payload i k → ( Vec i ) {
    : V e ( mkv )
    ?? e { VA s → { : ( Vec i ) t s ^ t } VB j → {} }
    ^ ( vec_new [i] )
}

: Holder { String name i n }
: P1 { String a }
: O2 { P1 p String b }

@ nested_lit Holder h → O2 { ^ @ O2 { @ P1 { . h name } ( string_from `a fresh field beside a nested one, long` ) } }

@ main → i {
    ( nurl_println ( string_data ( bound_first 1 ) ) )
    ( nurl_println ( string_data ( join_value 1 ) ) )
    ( nurl_println ( string_data ( through_gid 1 ) ) )
    : String q ( string_from `the caller's own argument, long enough heap` )
    ( nurl_println ( string_data ( through_pick q 0 ) ) )
    ( nurl_println ( string_data ( through_pick q 1 ) ) )
    ( nurl_println ( string_data ( alias_of_alias 1 ) ) )
    ( nurl_println ( string_data ( owned_outright 1 ) ) )
    ( nurl_println ( string_data ( of_a_sink ( mke `a sunk enum's payload, long enough for heap` ) ) ) )
    : ( Vec i ) v ( vec_payload 1 )
    : Holder h @ Holder { ( string_from `the holder's name, long enough for the heap` ) 1 }
    : O2 o ( nested_lit h )
    ( nurl_println ( string_data . . o p a ) )
    ( nurl_println ( string_data . o b ) )
    ( nurl_println ( string_data . h name ) )
    ( nurl_println ( string_data q ) )
    ^ - ( vec_len [i] v ) 1
}
