// char_extra.nu — offline acceptance test for the ASCII helpers added
// to stdlib/core/char.nu (is_upper / is_lower / is_hexdigit /
// to_upper_ascii / to_lower_ascii / hex_val).
//
// Determinism: pure byte arithmetic, no clock/socket/env. ASan-clean.

$ `stdlib/core/char.nu`

@ ck s label i got i want → v {
    ( nurl_print label )
    ( nurl_print ? == got want ` ok = ` ` MISMATCH = ` )
    ( nurl_print_int got )
}

@ main → i {
    // 'A'=65 'z'=122 '5'=53 'f'=102 'G'=71 ' '=32 '_'=95
    ( ck `is_upper(A) ` ( is_upper 65 ) 1 )
    ( ck `is_upper(z) ` ( is_upper 122 ) 0 )
    ( ck `is_upper(5) ` ( is_upper 53 ) 0 )

    ( ck `is_lower(z) ` ( is_lower 122 ) 1 )
    ( ck `is_lower(A) ` ( is_lower 65 ) 0 )

    ( ck `hexd(5)     ` ( is_hexdigit 53 ) 1 )
    ( ck `hexd(f)     ` ( is_hexdigit 102 ) 1 )
    ( ck `hexd(F)     ` ( is_hexdigit 70 ) 1 )
    ( ck `hexd(G)     ` ( is_hexdigit 71 ) 0 )
    ( ck `hexd(space) ` ( is_hexdigit 32 ) 0 )

    ( ck `up(a)       ` ( to_upper_ascii 97 ) 65 )
    ( ck `up(A)       ` ( to_upper_ascii 65 ) 65 )
    ( ck `up(5)       ` ( to_upper_ascii 53 ) 53 )

    ( ck `lo(Z)       ` ( to_lower_ascii 90 ) 122 )
    ( ck `lo(z)       ` ( to_lower_ascii 122 ) 122 )
    ( ck `lo(_)       ` ( to_lower_ascii 95 ) 95 )

    ( ck `hv(0)       ` ( hex_val 48 ) 0 )
    ( ck `hv(9)       ` ( hex_val 57 ) 9 )
    ( ck `hv(a)       ` ( hex_val 97 ) 10 )
    ( ck `hv(F)       ` ( hex_val 70 ) 15 )
    ( ck `hv(G)       ` ( hex_val 71 ) -1 )

    ^ 0
}
