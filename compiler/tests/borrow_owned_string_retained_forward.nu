// Forward and named retaining calls have the same ownership move effect.
$ `stdlib/core/string.nu`

@ main → i {
    : s raw ( nurl_argv_get 0 )
    : String owner ( retain value : raw )
    ( nurl_println raw )
    ( string_free owner )
    ^ 0
}

@ retain s value → String { ^ ( string_adopt value ) }
