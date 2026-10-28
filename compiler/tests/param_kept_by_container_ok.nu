// param_kept_by_container_ok.nu — a parameter a container keeps (agora
// #152): the container owns it from the push on, and the caller's value
// is released once, by the container.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ keep_it inout ( Vec String ) out String s → v { ( vec_push [String] out s ) }

@ keep_a_copy inout ( Vec String ) out String s → v {
    ( vec_push [String] out ( string_clone s ) )
    ( nurl_println ( string_data s ) )
}

@ main → i {
    : ~ ( Vec String ) out ( vec_new [String] )
    ( keep_it out ( string_from `kept` ) )
    ( keep_a_copy out ( string_from `copied` ) )
    : ~ i k 0
    ~ < k ( vec_len [String] out ) {
        ( nurl_println ( string_data ( vec_at [String] out k ) ) )
        = k + k 1
    }
    ( vec_free [String] out )
    ^ 0
}
