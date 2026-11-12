// diag_exclusive_call_bound_names_its_line.nu — the exclusive-call error
// for a call whose value a `:` binds names the call's own line (Agora
// #773): the row was recorded where the lexer stood after the call — the
// next statement — so the caret sat under `^ k`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ clr inout ( Vec String ) v String s → i {
    ( vec_clear [String] v )
    ^ ( strlen ( string_data s ) )
}

@ main → i {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : String e ( vec_at [String] t 0 )
    : i k ( clr t e )
    ^ k
}
