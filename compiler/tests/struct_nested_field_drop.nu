// Test: Phase 2D nested owned struct-field auto-drop. When an outer
// struct contains an inner struct whose field is a fresh allocation
// (here `msg` is i8* from nurl_str_cat), the drop emitted at scope exit
// must reach through the outer into the inner and free the inner's
// owned field. As with sibling tests we can't directly observe the
// free from NURL code; this exercises the dotted-path extractvalue +
// free path under ASan-style runs and verifies the user-visible
// round-trip reads the right bytes.

: Inner {
    s msg
    i n
}

: Outer {
    Inner inner
    i tag
}

@ main → i {
    : Outer o @ Outer { @ Inner { ( nurl_str_cat `hello ` `nested` ) 3 } 7 }
    ( nurl_print . . o inner msg ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int . . o inner n ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int . o tag ) ) ( nurl_print `\n` )

    // Second binding in a nested scope — drop must fire at each site.
    ? 1
    { : Outer o2 @ Outer { @ Inner { ( nurl_str_cat3 `a ` `b ` `c` ) 9 } 11 }
        ( nurl_print . . o2 inner msg ) ( nurl_print `\n` )
        ( nurl_print ( nurl_str_int . o2 tag ) ) ( nurl_print `\n` )
    }
    {}

    ^ 0
}
