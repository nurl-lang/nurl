// H648: agora #155 — a call's enum with a closure payload matched unbound in a loop (enum_closure_temp_matched_in_a_loop).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer.
: | E {
    Cb ( @ i )
    NoVal
}

@ make i v → E { ^ @ E { Cb \ → i { ^ + v 1 } } }

@ main → i {
    : ~ i n 0
    : ~ i acc 0
    ~ < n 100 {
        ?? ( make n ) {
            Cb f → { = acc + acc ( f ) }
            NoVal → {}
        }
        = n + n 1
    }
    ( nurl_println_int acc )
    ^ 0
}
