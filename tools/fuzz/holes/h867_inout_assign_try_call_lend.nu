// H867: agora #196 — the same through a try `\ ( getr w )` (inout_assign_try_call_lend).
// Closed: An `inout` parameter assigned a call's value — or a block's or a try's ending in one — that may lend out of this function's locals gets a copy where it lent, and the caller's old value is dropped there; a value that cannot be copied is refused (agora #196).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) } }

@ fill inout String io → !i E {
    : W w ( mkw )
    = io \ ( getr w )
    ^ @ !i E { T 1 }
}

@ main → i {
    : ~ String t ( string_from `start` )
    ?? ( fill t ) { T n → ( nurl_println_int + n ( string_len t ) ) F _ → ( nurl_println `bad` ) }
    ^ 0
}
