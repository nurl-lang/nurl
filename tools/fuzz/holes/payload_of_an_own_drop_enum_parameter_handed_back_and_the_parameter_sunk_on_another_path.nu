// payload_of_an_own_drop_enum_parameter_handed_back_and_the_parameter_sunk_on_another_path: a function hands back a String payload of its by-value parameter, an enum with a `% Drop` of its own, on one path, and hands the parameter to a `sink` on another.
// Closed with agora #641: the function is an inferred sink of the parameter (known at module end), so it drops the enum on every way out, and nothing is taken out of an enum with a `% Drop` of its own: the payload it lent back would be the caller's to read after the glue released it. Refused at module end (resolve_udrop_param_lends); declared `sink`, the payload is copied. Before the glue the payloads leaked, so the lend held.
// main c8c3f4d: accepted, heap-use-after-free in main (g drops the enum on the way out, the caller copies the payload it was lent).
// map: §7.6 | A2 | rejected | - | agora #641: a payload of an own-% Drop enum parameter handed back on one path while another path hands the parameter to a sink (the function drops the enum on the way out)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E2 { Zero2 i Three2 Bomb String Bomb One2 String }

% Drop E2 { @ drop E2 e → v { ( nurl_println `drop enum E2` ) } }

@ mk s a → E2 { ^ @ E2 { Three2 ( bomb ( nurl_str_cat a `.a` ) ) ( string_from `3s, long enough for the heap` ) ( bomb ( nurl_str_cat a `.c` ) ) } }

@ eat sink E2 e → v { ( nurl_println `eat` ) }

@ g E2 e → String {
    ?? e {
        Zero2 n → {}
        Three2 x s y → { ( eat e ) ^ ( string_from `sunk` ) }
        One2 s → { ^ s }
    }
    ^ ( string_from `zero` )
}

@ main → i {
    : String a ( g ( mk `q` ) )
    ( nurl_println ( string_data a ) )
    : String b ( g @ E2 { One2 ( string_from `one, long enough for the heap` ) } )
    ( nurl_println ( string_data b ) )
    ^ 0
}
