// Forward and named retaining calls have the same ownership move effect.
$ `stdlib/core/string.nu`

@ main → i {
    : s raw ( nurl_argv_get 0 )
    : String owner ( retain value : raw capacity : + ( nurl_str_len raw ) 1 )
    ( nurl_println raw )
    ( string_free owner )
    ^ 0
}

@ retain s value i capacity → String { ^ ( string_from_take value capacity ) }
