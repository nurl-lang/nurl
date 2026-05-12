// Owned String — dynamic string construction (formerly StringBuilder).
// Vec[u]-backed since 2026-05-01; the SB runtime API has been retired.

$ `stdlib/core/string.nu`

@ main → i {
    ( nurl_print `StringBuilder test...\n` )

    // Create
    : String sb ( string_new )

    // Append strings
    ( string_push_str sb `hello` )
    ( string_push_str sb ` ` )
    ( string_push_str sb `world` )

    // Build and print
    ( nurl_print `basic: ` )
    ( nurl_print ( string_data sb ) )
    ( nurl_print `\n` )

    // Length
    ( nurl_print `length: ` )
    ( nurl_print ( nurl_str_int ( string_len sb ) ) )
    ( nurl_print `\n` )

    // Append int
    ( string_push_int sb 42 )
    ( nurl_print `after int: ` )
    ( nurl_print ( string_data sb ) )
    ( nurl_print `\n` )

    // Append float
    ( string_push_float sb 3.14 )
    ( nurl_print `after float: ` )
    ( nurl_print ( string_data sb ) )
    ( nurl_print `\n` )

    // Clear and reuse
    ( string_clear sb )
    ( nurl_print `after clear len: ` )
    ( nurl_print ( nurl_str_int ( string_len sb ) ) )
    ( nurl_print `\n` )

    // Build CSV row
    ( string_push_str sb `name` )
    ( string_push_str sb `,` )
    ( string_push_str sb `age` )
    ( string_push_str sb `,` )
    ( string_push_str sb `score` )
    ( string_push_str sb `\n` )
    ( string_push_str sb `alice` )
    ( string_push_str sb `,` )
    ( string_push_int sb 30 )
    ( string_push_str sb `,` )
    ( string_push_int sb 95 )

    ( nurl_print `csv:\n` )
    ( nurl_print ( string_data sb ) )
    ( nurl_print `\n` )

    // Cleanup
    ( string_free sb )

    ( nurl_print `done\n` )
    ^ 0
}
