// closure_block_tail_getter: agora #187 — a closure's `^ { : W w … ( gets w ) }` (closure_block_tail_getter).
// Closed: `^` of a block whose tail is a call (through nested blocks: g_blk_tail_eff) is a call return (ret_eff_tt): what the call lends of a local is copied, or refused when it cannot be, and a string it hands over is the caller's (agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h827 | agora #187: a closure's `^ { : W w … ( gets w ) }`
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ main → i {
    : ( @ String ) f \ → String {
        ^ {
            : W w @ W { ( string_from `element string long enough for a heap buffer` ) }
            ( gets w )
        }
    }
    : String a ( f )
    ( nurl_println_int ( string_len a ) )
    ^ 0
}
