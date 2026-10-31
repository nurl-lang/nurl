// enum_closure_payload_returned_from_a_frame: agora #155 — a closure literal as an enum payload, returned (enum_closure_payload_returned_from_a_frame).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer (the closure env).
// map: §7.6 | A2 | runs-clean | h640 | agora #155: a closure literal as an enum payload, returned
: | E {
    Cb ( @ i )
    NoVal
}

@ make_e i d i v → E {
    ? > d 0 { ^ ( make_e - d 1 v ) } {}
    ^ @ E { Cb \ → i { ^ v } }
}

@ main → i {
    : E e ( make_e 1 42 )
    ?? e {
        Cb f → { ( nurl_println ( nurl_str_int ( f ) ) ) }
        NoVal → {}
    }
    ^ 0
}
