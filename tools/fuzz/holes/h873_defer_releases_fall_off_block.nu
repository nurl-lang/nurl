// H873: agora #197 — the same with the block as the function's fall-off value (defer_releases_fall_off_block).
// Closed: gen_ret records the owner a block's tail names as the one the return hands back (`rto_`), as for `^ l`: a `;` defer that releases it is refused (agora #197).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

@ keep sink String d → v { ( nurl_println_int ( string_len d ) ) }

@ pick → String {
    : String l ( string_from `a local string long enough for a heap buffer` )
    ; { ( keep l ) }
    {
        : i z 1
        l
    }
}

@ main → i {
    : String r ( pick )
    ( nurl_println_int ( string_len r ) )
    ^ 0
}
