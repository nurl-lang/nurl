// dyn_of_a_view_struct_literal_returned: agora #156 — a struct literal viewing a local String, boxed with dyn and returned (dyn_of_a_view_struct_literal_returned).
// Closed: a dyn object holds what its operand held — its stack referent, its parameter carriers and its source expression (gen_dyn_construct; agora #156).
// v0.80.0: accepted; LeakSanitizer (the String the object views was never released).
// map: §2.11 | A2 | rejected | h633 | agora #156: a struct literal viewing a local String, boxed with dyn and returned
$ `stdlib/core/string.nu`

% Show [T] {
    @ len T self → i
}

: V { s p i pad }

% Show V { @ len V v → i { ^ ( nurl_str_len . v p ) } }

@ mk → %Show {
    : String s ( string_from `a string long enough to own a heap buffer here` )
    ^ ( dyn Show @ V { ( string_data s ) 0 } )
}

@ main → i {
    : %Show r ( mk )
    ( nurl_println_int ( len r ) )
    ^ 0
}
