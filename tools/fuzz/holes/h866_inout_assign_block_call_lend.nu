// H866: agora #196 — the same through a block ending in the call (inout_assign_block_call_lend).
// Closed: An `inout` parameter assigned a call's value — or a block's or a try's ending in one — that may lend out of this function's locals gets a copy where it lent, and the caller's old value is dropped there; a value that cannot be copied is refused (agora #196).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: W { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ fill inout String io → v {
    = io {
        : W w ( mkw )
        ( gets w )
    }
}

@ main → i {
    : ~ String t ( string_from `start` )
    ( fill t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
