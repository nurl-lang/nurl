// H822: agora #187 — `^ { : W w … ( getd w ) }`: a block whose tail call lends its own local (drop_block_tail_getter).
// Closed: `^` of a block whose tail is a call (through nested blocks: g_blk_tail_eff) is a call return (ret_eff_tt): what the call lends of a local is copied, or refused when it cannot be, and a string it hands over is the caller's (agora #187).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: W { D d }

@ getd W w → D { ^ . w d }

@ mk → D { ^ @ D { ( string_from `element string long enough for a heap buffer` ) } }

@ pick → D {
    ^ {
        : W w @ W { ( mk ) }
        ( getd w )
    }
}

@ main → i {
    : D a ( pick )
    ( nurl_println_int ( string_len . a s ) )
    ^ 0
}
