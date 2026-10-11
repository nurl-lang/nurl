// Forward and named retaining calls have the same ownership effect. In safe
// code only a declared `sink` takes a raw string over: `retain` hands its
// borrowed parameter to string_adopt, which is given a copy, and the caller
// keeps its own string — reads it afterwards, and frees it at the end.
$ `stdlib/core/string.nu`

@ main → i {
    : s raw ( nurl_str_cat `ab` `cd` )
    : String a ( retain raw )
    : String b ( retain value : raw )
    ( nurl_println raw )
    ( nurl_println_int + ( string_len a ) ( string_len b ) )
    ^ 0
}

@ retain s value → String { ^ ( string_adopt value ) }
