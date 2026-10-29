// H641: agora #155 — an enum payload closure that captured a local String, returned (enum_closure_payload_capturing_a_string).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer (the env and its String).
$ `stdlib/core/string.nu`

: | E {
    Cb ( @ i )
    NoVal
}

@ make → E {
    : String s ( string_from `hello world, long enough for a heap buffer` )
    ^ @ E { Cb \ → i { ^ ( string_len s ) } }
}

@ main → i {
    : E e ( make )
    ?? e {
        Cb f → { ( nurl_println_int ( f ) ) }
        NoVal → {}
    }
    ^ 0
}
