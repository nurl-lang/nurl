// H609: agora #172 — callee hands back one field of the literal: the binding still drops its value in the rest (literal_with_a_binding_value_part_handed_back).
// Closed: a literal its callee hands back whole moves a binding's value in, as for a callee that keeps it (__agg_arg_lend__, mem_note_kept_arg; agora #172).
// v0.80.0: accepted; AddressSanitizer reported a heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: V2 { ( Vec String ) xs String s }

@ pick V2 v → String { ^ . v s }

@ main → i {
    : ( Vec String ) b ( vec_new [String] )
    ( vec_push [String] b ( mk ) )
    : String r ( pick @ V2 { b ( mk ) } )
    ( nurl_println ( string_data r ) )
    ( nurl_println_int ( vec_len [String] b ) )
    ^ 0
}
