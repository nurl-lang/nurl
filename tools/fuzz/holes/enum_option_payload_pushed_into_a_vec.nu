// enum_option_payload_pushed_into_a_vec: agora #155 — enums with option payloads pushed into a Vec the caller drops (enum_option_payload_pushed_into_a_vec).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h644 | agora #155: enums with option payloads pushed into a Vec the caller drops
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E {
    Opt ? String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill ( Vec E ) v → v {
    : ~ i n 0
    ~ < n 3 {
        ( vec_push [E] v @ E { Opt @ ?String { T ( mk ) } } )
        = n + n 1
    }
}

@ main → i {
    : ( Vec E ) v ( vec_new [E] )
    ( fill v )
    ( nurl_println_int ( vec_len [E] v ) )
    ^ 0
}
