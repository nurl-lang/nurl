// diag_join_view_kept_past_statement.nu — a `?` / `??` join with an arm that
// owns its value is a temporary of the call it is handed to; a view of it
// (`string_data`) kept past the statement could never be released without
// leaving the view dangling, so it is refused with the cure: bind the join
// first (agora #181, h732).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `kept` ) )
    : s w ( string_data ?? ( vec_get [String] v 1 ) { T x → x F _ → ( string_from `fresh` ) } )
    ( nurl_println w )
    ^ 0
}
