// H653: agora #155 — a call's enum with a closure payload matched unbound once (enum_closure_temp_matched_once).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer (the closure env).
: | E {
    Cb ( @ i )
    NoVal
}

@ make i v → E { ^ @ E { Cb \ → i { ^ + v 1 } } }

@ main → i {
    ?? ( make 41 ) {
        Cb f → { ( nurl_println_int ( f ) ) }
        NoVal → {}
    }
    ^ 0
}
