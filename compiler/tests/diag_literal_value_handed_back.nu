// diag_literal_value_handed_back.nu — a literal built as an argument takes
// a binding's value with it when its callee hands the literal back whole
// (agora #172): the result owns that value, so the binding is moved.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: V2 { ( Vec String ) xs String s }

@ pass V2 v → V2 { ^ v }

@ id [T] T v → T { ^ v }

@ main → i {
    : ( Vec String ) b ( vec_new [String] )
    ( vec_push [String] b ( mk ) )
    : V2 r ( pass @ V2 { b ( mk ) } )
    ( nurl_println_int ( vec_len [String] b ) )
    : String t ( mk )
    : V2 q ( id [V2] @ V2 { ( vec_new [String] ) t } )
    ( nurl_println ( string_data t ) )
    ^ 0
}
