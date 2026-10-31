// dyn_of_a_view_struct_outlives_its_owner: agora #156 — a dyn object over a view assigned to an outer binding, read after the String ended (dyn_of_a_view_struct_outlives_its_owner).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h635 | agora #156: a dyn object over a view assigned to an outer binding, read after the String ended
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

@ main → i {
    : ~ % Show r ( dyn Show @ V { `static` 0 } )
    {
        : String s ( string_from `a string long enough to own a heap buffer here` )
        = r ( dyn Show @ V { ( string_data s ) 0 } )
    }
    ( nurl_println_int ( len r ) )
    ^ 0
}
