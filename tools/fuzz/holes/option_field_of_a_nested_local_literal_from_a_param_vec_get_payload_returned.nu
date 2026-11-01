// option_field_of_a_nested_local_literal_from_a_param_vec_get_payload_returned: agora #300 — (f4) an option field two literals deep in a local struct, made from a parameter Vec's vec_get, its payload returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (f4) an option field two literals deep in a local struct, made from a parameter Vec's vec_get, its payload returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: H { ? String o }
: G { H a }

@ pick ( Vec String ) ps → String {
    : G g @ G { @ H { ( vec_get [String] ps 0 ) } }
    ?? . . g a o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : ( Vec String ) ps ( vec_new [String] )
    ( vec_push [String] ps ( string_from `a parameter element long enough for the heap` ) )
    : String s ( pick ps )
    ( nurl_println ( string_data s ) )
    ^ 0
}
