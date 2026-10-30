// H874: agora #197 — a defer that only reads the local the block hands back: allowed (defer_reads_block_returned).
// Closed: gen_ret records the owner a block's tail names as the one the return hands back (`rto_`), as for `^ l`: a `;` defer that releases it is refused (agora #197).
// main: accepted and ran clean (kept as a guard).
$ `stdlib/core/string.nu`

: R { String s }

@ keep sink String d → v { ( nurl_println_int ( string_len d ) ) }

@ pick → String {
    : String l ( string_from `a local string long enough for a heap buffer` )
    ; { ( nurl_println_int ( string_len l ) ) }
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
