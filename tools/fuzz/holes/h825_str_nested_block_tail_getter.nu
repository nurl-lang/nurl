// H825: agora #187 — the String case through a nested block (str_nested_block_tail_getter).
// Closed: `^` of a block whose tail is a call (through nested blocks: g_blk_tail_eff) is a call return (ret_eff_tt): what the call lends of a local is copied, or refused when it cannot be, and a string it hands over is the caller's (agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ pick → String {
    ^ {
        : W w @ W { ( string_from `element string long enough for a heap buffer` ) }
        {
            : i z 1
            ( gets w )
        }
    }
}

@ main → i {
    : String a ( pick )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
