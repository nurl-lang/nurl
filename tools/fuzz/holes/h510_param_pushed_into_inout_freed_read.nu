// H510: agora #152 — a parameter handed to a container that keeps it (param_pushed_into_inout_freed_read).
// Closed: the store row now covers parameters (agora #152).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ keep_and_read inout ( Vec String ) out String s → v {
    ( vec_push [String] out s )
    ( vec_free [String] out )
    ( nurl_println ( string_data s ) )
}

@ main → i { : ~ ( Vec String ) out ( vec_new [String] ) : String s ( mk ) ( keep_and_read out s ) ^ 0 }
