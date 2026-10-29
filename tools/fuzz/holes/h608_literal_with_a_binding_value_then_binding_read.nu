// H608: agora #172 — binding read after its value went into a literal the callee handed back (literal_with_a_binding_value_then_binding_read).
// Closed: a literal its callee hands back whole moves a binding's value in, as for a callee that keeps it (__agg_arg_lend__, mem_note_kept_arg; agora #172).
// v0.80.0: accepted; AddressSanitizer reported a heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: V2 { ( Vec String ) xs String s }

@ pass V2 v → V2 { ^ v }

@ main → i {
    : ( Vec String ) b ( vec_new [String] )
    ( vec_push [String] b ( mk ) )
    : V2 r ( pass @ V2 { b ( mk ) } )
    ( nurl_println_int ( vec_len [String] b ) )
    ( nurl_println ( string_data . r s ) )
    ^ 0
}
