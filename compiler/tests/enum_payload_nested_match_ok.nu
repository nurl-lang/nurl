// enum_payload_nested_match_ok.nu — a match over an enum's payload that is
// itself an option or a result (agora #175).
// - The payload binding is lent by the enum, so a `% Drop` payload of it
//   is dropped once, by the enum.
// - Handing that payload's own payload out of an enum this function owns
//   takes the option out of the enum.
// Every drop line prints once; runs clean under the sanitizers.

$ `stdlib/core/string.nu`

: D { String s i n }

% Drop D { @ drop D d → v { ( nurl_println ( nurl_str_cat `drop ` ( nurl_str_int . d n ) ) ) } }

@ mkd i n → D { ^ @ D { ( string_from `a string long enough to own a heap buffer here` ) n } }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | E {
    Opt ? D
    Res ! D i
    Two i ? D
    Str ? String
    NoVal
}

@ inner sink E e → String { ^ ?? e { Str o → ?? o { T s → s F → ( mk ) } Opt o → ( mk ) Res r → ( mk ) Two k o → ( mk ) NoVal → ( mk ) } }

@ main → i {
    : E a @ E { Opt @ ?D { T ( mkd 1 ) } }
    ?? a { Opt o → { ?? o { T d → { ( nurl_println_int . d n ) } F → {} } } Res r → {} Two k o → {} Str o → {} NoVal → {} }
    : E b @ E { Res @ !D i { T ( mkd 2 ) } }
    ?? b { Res r → { ?? r { T d → { ( nurl_println_int . d n ) } F x → {} } } Opt o → {} Two k o → {} Str o → {} NoVal → {} }
    : E c @ E { Two 3 @ ?D { T ( mkd 3 ) } }
    ?? c { Two k o → { ?? o { T d → { ( nurl_println_int + k . d n ) } F → {} } } Opt o → {} Res r → {} Str o → {} NoVal → {} }
    : String t ( inner @ E { Str @ ?String { T ( mk ) } } )
    : ~ E e @ E { Str @ ?String { T ( mk ) } }
    : String u ?? e { Str o → ?? o { T s → s F → ( mk ) } Opt o → ( mk ) Res r → ( mk ) Two k o → ( mk ) NoVal → ( mk ) }
    = e @ E { NoVal }
    ( nurl_println_int + ( string_len t ) ( string_len u ) )
    ^ 0
}
