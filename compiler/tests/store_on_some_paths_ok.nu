// store_on_some_paths_ok.nu — a value handed to an owner at exactly one
// place on each path (agora #160): the key found first, then stored once;
// a closure capture stored with a loop-local option, read again on the
// next iteration. Each runs clean.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ put_or_append ( Vec String ) v s key String val → v {
    : ~ i found -1
    : ~ i k 0
    ~ & < found 0 < k ( vec_len [String] v ) {
        ? != 0 ( nurl_str_eq ( string_data ( vec_at [String] v k ) ) key ) { = found k } {}
        = k + k 1
    }
    ? >= found 0 { ( vec_set [String] v found val ) } { ( vec_push [String] v val ) }
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a` ) )
    ( put_or_append v `a` ( string_from `b` ) )
    ( put_or_append v `z` ( string_from `c` ) )
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    ( nurl_println ( string_data ( vec_at [String] v 1 ) ) )
    ( vec_free [String] v )
    : String a ( string_from `captured` )
    : ~ i k 0
    ~ < k 2 {
        : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
        : ?( @ i i ) lo @ ?( @ i i ) { T f }
        ?? lo { T g → { ( nurl_println_int ( g k ) ) } F → {} }
        = k + k 1
    }
    ^ 0
}
