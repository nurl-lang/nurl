// enum_temp_matched_in_a_loop_ok.nu — a match over an enum a call hands
// over (`?? ( make n ) { … }`) owns that enum until the scope ends (h233).
// In a loop's body the scope ends every round, and the round after it
// released the same enum again. Now the scope's drop marks it gone (agora
// #155). Every round, after `continue` and after `break`, runs clean under
// the sanitizers.

$ `stdlib/core/string.nu`

: P { String s i n }

: | E {
    V P
    Cb ( @ i )
    NoVal
}

@ make i v → E {
    ? == 0 % v 2 { ^ @ E { Cb \ → i { ^ + v 1 } } } {}
    ^ @ E { V @ P { ( string_from `a string long enough to own a heap buffer here` ) v } }
}

@ main → i {
    : ~ i n 0
    : ~ i acc 0
    ~ < n 30 {
        = n + n 1
        ?? ( make n ) {
            V p → {
                ? == 0 % . p n 3 { continue } {}
                = acc + acc + . p n ( string_len . p s )
            }
            Cb f → { = acc + acc ( f ) }
            NoVal → {}
        }
    }
    ( nurl_println_int acc )
    = n 0
    ~ < n 30 {
        = n + n 1
        ?? ( make n ) {
            V p → { ? > . p n 20 { break } {} }
            Cb f → { = acc + acc ( f ) }
            NoVal → {}
        }
    }
    ( nurl_println_int acc )
    ^ 0
}
