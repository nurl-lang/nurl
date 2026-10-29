// diag_store_on_some_paths.nu — a value stored into an owner on some
// paths only, or on every iteration of a loop (agora #160): read after
// the owner let it go, freed, or stored again, it is released twice on
// the path that stored it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ read_after_its_owner_went b c → v {
    : String s ( mk )
    : ( Vec String ) v ( vec_new [String] )
    ? c { ( vec_push [String] v s ) } {}
    ( vec_free [String] v )
    ( nurl_println ( string_data s ) )
}

@ freed_after b c → v {
    : String s ( mk )
    : ( Vec String ) v ( vec_new [String] )
    ? c { ( vec_push [String] v s ) } {}
    ( string_free s )
    ( vec_free [String] v )
}

@ stored_every_iteration → v {
    : String s ( mk )
    : ( Vec String ) v ( vec_new [String] )
    : ~ i k 0
    ~ < k 2 {
        ( vec_push [String] v s )
        = k + k 1
    }
    ( vec_free [String] v )
}

@ main → i { ^ 0 }
