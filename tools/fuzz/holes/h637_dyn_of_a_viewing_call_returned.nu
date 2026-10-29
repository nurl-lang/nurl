// H637: agora #156 — a call result viewing a local String, boxed with dyn and returned (dyn_of_a_viewing_call_returned).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

@ mkv String s → V { ^ @ V { ( string_data s ) 0 } }

@ mk → %Show {
    : String s ( string_from `a string long enough to own a heap buffer here` )
    ^ ( dyn Show ( mkv s ) )
}

@ main → i {
    : %Show r ( mk )
    ( nurl_println_int ( len r ) )
    ^ 0
}
