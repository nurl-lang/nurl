// diag_defer_releases_block_returned.nu — a `;` defer runs after the
// returned value is the caller's: one that releases the local a block's
// tail hands back (`^ { … l }`) would free it under the caller, as for a
// bare `^ l` (agora #197).

$ `stdlib/core/string.nu`

@ keep sink String d → v { ( nurl_println_int ( string_len d ) ) }

@ pick → String {
    : String l ( string_from `a local string long enough for a heap buffer` )
    ; { ( keep l ) }
    ^ {
        : i z 1
        l
    }
}

@ main → i {
    : String r ( pick )
    ( nurl_println_int ( string_len r ) )
    ^ 0
}
