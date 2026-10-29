// H646: agora #155 — an enum closure payload capturing a String, rebound in a match arm (enum_closure_payload_bound_in_an_arm).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: | E {
    Cb ( @ i )
    NoVal
}

@ main → i {
    : String s ( string_from `hello world, long enough for a heap buffer` )
    : E e @ E { Cb \ → i { ^ ( string_len s ) } }
    ?? e {
        Cb f → {
            : ( @ i ) g f
            ( nurl_println_int ( g ) )
        }
        NoVal → {}
    }
    ^ 0
}
