// param_pushed_then_returned: agora #152 — a parameter handed to a container that keeps it (param_pushed_then_returned).
// Closed: the store row now covers parameters (agora #152).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.12 | A2 | rejected | h509 | agora #152: param_pushed_then_returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ push_and_ret String s → String {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out s )
    ^ s
}

@ main → i { : String s ( mk ) : String r ( push_and_ret s ) ( nurl_println ( string_data r ) ) ^ 0 }
