// str_block_tail_param: agora #187 — a block whose tail call lends a parameter: still a lend, no copy (str_block_tail_param).
// Closed: `^` of a block whose tail is a call (through nested blocks: g_blk_tail_eff) is a call return (ret_eff_tt): what the call lends of a local is copied, or refused when it cannot be, and a string it hands over is the caller's (agora #187).
// main: accepted and ran clean (kept as a guard: the lend stays a lend).
// map: §7.6 | A2 | runs-clean | h824 | agora #187: a block whose tail call lends a parameter: still a lend, no copy
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ pick W w → String {
    ^ {
        : i z 0
        ( gets w )
    }
}

@ main → i {
    : W w @ W { ( string_from `element string long enough for a heap buffer` ) }
    : String a ( pick w )
    ( nurl_println_int + ( string_len a ) ( string_len . w s ) )
    ^ 0
}
