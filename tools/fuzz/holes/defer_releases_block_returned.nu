// defer_releases_block_returned: agora #197 — `; { ( keep l ) }  ^ { : i z 1 l }`: the defer hands `l` to a `sink` after the block returned it (defer_releases_block_returned).
// Closed: gen_ret records the owner a block's tail names as the one the return hands back (`rto_`), as for `^ l`: a `;` defer that releases it is refused (agora #197).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h872 | agora #197: `; { ( keep l ) }  ^ { : i z 1 l }`: the defer hands `l` to a `sink` after the block returned it
$ `stdlib/core/string.nu`

: R { String s }

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
