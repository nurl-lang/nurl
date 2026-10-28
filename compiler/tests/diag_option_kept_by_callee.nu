// diag_option_kept_by_callee.nu — an option of a String kept by a callee
// is stored in the container it is handed with (agora #149): released
// with the container, it may not be read afterwards — directly, through a
// helper that pushes its option parameter, or one that pushes the
// parameter's payload.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ keep_opt ( Vec ? String ) out ? String o → v { ( vec_push [? String] out o ) }

@ keep_payload ( Vec String ) out ? String o → v { ?? o { T s → { ( vec_push [String] out s ) } F → {} } }

@ direct → v {
    : ( Vec ? String ) out ( vec_new [? String] )
    : ?String o @ ?String { T ( mk ) }
    ( vec_push [? String] out o )
    ( vec_free [? String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ through_helper → v {
    : ( Vec ? String ) out ( vec_new [? String] )
    : ?String o @ ?String { T ( mk ) }
    ( keep_opt out o )
    ( vec_free [? String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ payload_through_helper → v {
    : ( Vec String ) out ( vec_new [String] )
    : ?String o @ ?String { T ( mk ) }
    ( keep_payload out o )
    ( vec_free [String] out )
    ?? o { T x → { ( nurl_println ( string_data x ) ) } F → {} }
}

@ main → i { ^ 0 }
