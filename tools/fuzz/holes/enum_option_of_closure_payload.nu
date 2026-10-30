// enum_option_of_closure_payload: agora #155 — an enum payload that is an option of a closure (enum_option_of_closure_payload).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h649 | agora #155: an enum payload that is an option of a closure
: | E {
    Opt ? ( @ i )
    NoVal
}

@ make i v → E { ^ @ E { Opt @ ?( @ i ) { T \ → i { ^ + v 1 } } } }

@ main → i {
    : E e ( make 41 )
    ?? e {
        Opt o → { ?? o { T f → { ( nurl_println_int ( f ) ) } F → {} } }
        NoVal → {}
    }
    ^ 0
}
