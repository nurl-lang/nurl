// param_pushed_then_freed: agora #152 — a parameter handed to a container that keeps it (param_pushed_then_freed).
// Closed: the store row now covers parameters (agora #152).
// v0.80.0: accepted; AddressSanitizer reported a fault.
// map: §2.12 | A2 | rejected | h508 | agora #152: param_pushed_then_freed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ push_and_free String s → v {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out s )
    ( string_free s )
}

@ main → i { : String s ( mk ) ( push_and_free s ) ^ 0 }
