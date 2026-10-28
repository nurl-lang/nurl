// diag_param_kept_by_container.nu — a parameter handed to a container that
// keeps it (agora #152). The callee owns its parameter, so vec_push makes
// the value the container's: a later read, a second push or a return of
// the parameter reaches memory the container releases.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ read_after_free String s → v {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out s )
    ( vec_free [String] out )
    ( nurl_println ( string_data s ) )
}

@ pushed_twice String s → v {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out s )
    ( vec_push [String] out s )
}

@ returned_after_push String s → String {
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out s )
    ^ s
}

@ main → i { ^ 0 }
