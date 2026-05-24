// Test: Phase 2B reassignment-drop. Re-assigning an owned i8* binding to a
// fresh allocating call should free the previous heap value, not leak it.
// We can't observe the free directly from NURL code; this test just exercises
// the path under valgrind/AddressSanitizer-style runs and verifies that
// reassignment still produces correct values for the user.

$ `stdlib/core/string.nu`

@ main → i {
    : ~ s greeting ( nurl_str_cat `hello ` `world` )
    ( nurl_print greeting ) ( nurl_print `\n` )
    = greeting ( nurl_str_cat `goodbye ` `world` )
    ( nurl_print greeting ) ( nurl_print `\n` )
    = greeting ( nurl_str_cat3 `one ` `two ` `three` )
    ( nurl_print greeting ) ( nurl_print `\n` )
    ^ 0
}
