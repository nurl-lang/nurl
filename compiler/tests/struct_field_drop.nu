// Test: Phase 2C struct-field auto-drop. A struct literal populated with
// a fresh allocating i8* call should free that field when the struct's
// binding goes out of scope. Like the sibling Phase 2B tests we can't
// observe the free directly from NURL code; this test exercises the
// path under valgrind / AddressSanitizer-style runs and verifies the
// user-visible behaviour (field reads still return the right bytes).

: Greeting {
    s msg
    i n
}

@ main → i {
    : Greeting g @ Greeting { ( nurl_str_cat `hello ` `world` ) 42 }
    ( nurl_print . g msg ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int . g n ) ) ( nurl_print `\n` )

    // A second struct in a nested scope ensures the drop fires at each
    // binding site, not just at fn exit.
    ? 1
    { : Greeting g2 @ Greeting { ( nurl_str_cat3 `one ` `two ` `three` ) 7 }
        ( nurl_print . g2 msg ) ( nurl_print `\n` )
    }
    {}

    ^ 0
}
