// H636: agora #156 — a struct field viewing a local String, boxed with dyn and returned (dyn_of_a_view_field_returned).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

: W { V v i n }

@ mk → %Show {
    : String s ( string_from `a string long enough to own a heap buffer here` )
    : W w @ W { @ V { ( string_data s ) 0 } 1 }
    ^ ( dyn Show . w v )
}

@ main → i {
    : %Show r ( mk )
    ( nurl_println_int ( len r ) )
    ^ 0
}
