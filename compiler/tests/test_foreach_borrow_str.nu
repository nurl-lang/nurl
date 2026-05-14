// test_foreach_borrow_str.nu
// Test: Ownership of strings in foreach loop (Borrow).

@ main → i {
    : [s ss [s | `one` `two` `three`]

    ( nurl_print `Start foreach\n` )
    ~ val ss {
        ( nurl_print `Val: ` )
        ( nurl_print val )
        ( nurl_print `\n` )
    }
    ( nurl_print `End foreach\n` )

    ^ 0
}
