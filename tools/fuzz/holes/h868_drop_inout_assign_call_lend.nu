// H868: agora #196 — the same with a `% Drop` value: it cannot be copied (drop_inout_assign_call_lend).
// Closed: An `inout` parameter assigned a call's value — or a block's or a try's ending in one — that may lend out of this function's locals gets a copy where it lent, and the caller's old value is dropped there; a value that cannot be copied is refused (agora #196).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ getd H h → D { ^ . h d }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ fill inout D io → v {
    : H h ( mkh )
    = io ( getd h )
}

@ main → i {
    : ~ D t @ D { ( string_from `start` ) }
    ( fill t )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
