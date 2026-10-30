// H871: agora #196 — the same with a `% Drop` field: it cannot be copied (drop_inout_assign_local_field).
// Closed: A field read of a value this frame owns, assigned to an `inout` parameter, is copied and the caller's old value dropped; one that cannot be copied is refused (agora #196).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: H { D d }

@ mkh → H { ^ @ H { @ D { ( string_from `a string long enough for a heap buffer` ) } } }

@ fill inout D io → v {
    : H h ( mkh )
    = io . h d
}

@ main → i {
    : ~ D t @ D { ( string_from `start` ) }
    ( fill t )
    ( nurl_println_int ( string_len . t s ) )
    ^ 0
}
