// A raw string's buffer belongs to the returned String after adoption.
$ `stdlib/core/string.nu`

@ main → i {
    : s raw ( nurl_argv_get 0 )
    : String owner ( string_adopt raw )
    ( nurl_println raw )
    ( string_free owner )
    ^ 0
}
