// raw_view_block_tail: agora #187 — `^ { : String x … ( string_data x ) }`: a raw view of a block's own String (raw_view_block_tail).
// Closed: `^` of a block whose tail is a call (through nested blocks: g_blk_tail_eff) is a call return (ret_eff_tt): what the call lends of a local is copied, or refused when it cannot be, and a string it hands over is the caller's (agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h826 | agora #187: `^ { : String x … ( string_data x ) }`: a raw view of a block's own String
$ `stdlib/core/string.nu`

@ pick → s {
    ^ {
        : String x ( string_from `element string long enough for a heap buffer` )
        ( string_data x )
    }
}

@ main → i {
    : s a ( pick )
    ( nurl_println a )
    ^ 0
}
