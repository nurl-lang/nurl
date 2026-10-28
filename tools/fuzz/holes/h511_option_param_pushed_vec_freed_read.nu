// H511: agora #152 — a parameter handed to a container that keeps it (option_param_pushed_vec_freed_read).
// Closed: the store row now covers parameters (agora #152).
// v0.80.0: accepted; AddressSanitizer reported a fault.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ use_opt ? String o → v {
    : ( Vec ? String ) out ( vec_new [? String] )
    ( vec_push [? String] out o )
    ( vec_free [? String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ main → i { : ?String o @ ?String { T ( mk ) } ( use_opt o ) ^ 0 }
