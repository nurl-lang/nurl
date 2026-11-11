// diag_lend_bare_view_of_match_payload.nu — agora #578: a `??` payload
// reaches what the matched value does. A bare `s` view of it that an arm
// of a value join yields (`T e → ( string_data e )`) is a view of the
// parameter's element, so the function lends the parameter and the caller
// may not clear it while it reads the view (it used to compile: use after
// free).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first_str ( Vec String ) p → s {
    ^ ?? ( vec_get [String] p 0 ) {
        T e → ( string_data e )
        F → ``
    }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( first_str t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
