// store_into_owned_and_shared_copies.nu — the stores Agora #488 / #643 do
// NOT refuse, each landing where its owner looks and released once:
// a `sink` parameter (the function owns the copy and hands it back), an
// `inout` parameter, an owned local, a mutable binding a closure captures
// by pointer, a local that shadows a parameter's or a loop element's name,
// and a scalar field of a by-value parameter handed back. Warned: a scalar
// store into a loop element (lost), as a by-value parameter's is.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: App { String name i n }

@ renamed sink App a → App {
    = . a name ( string_from `renamed through a sink parameter, long enough` )
    ^ a
}

@ rename_in inout App a → v {
    = . a name ( string_from `renamed through an inout parameter, long enough` )
}

@ shadowed App a → i {
    : App a @ App { ( string_from `a local of the parameter's name, long enough` ) 2 }
    = . a name ( string_from `the local renamed, a name long enough for heap` )
    ( nurl_println ( string_data . a name ) )
    ^ . a n
}

@ bumped App a → App {
    = . a n + . a n 1
    ^ a
}

@ main → i {
    : App a @ App { ( string_from `the first name, also long enough to live on the heap` ) 1 }
    : App b ( renamed a )
    ( nurl_println ( string_data . b name ) )

    : ~ App c @ App { ( string_from `a second name, also long enough for the heap` ) 1 }
    ( rename_in c )
    ( nurl_println ( string_data . c name ) )

    : ~ App d @ App { ( string_from `a third name, also long enough for the heap` ) 1 }
    : ( @ v i ) f \ i k → v { = . d name ( string_from `renamed by a closure over a mutable binding` ) }
    ( f 1 )
    ( f 2 )
    ( nurl_println ( string_data . d name ) )

    : i k ( shadowed c )
    : App e ( bumped c )
    ( nurl_println_int . e n )

    : ( Vec App ) ps ( vec_new [App] )
    ( vec_push [App] ps @ App { ( string_from `an element's name, long enough for the heap` ) 1 } )
    ~ p ps {
        : App p @ App { ( string_from `a body local of the element's name, long` ) 3 }
        = . p name ( string_from `the body local renamed, long enough for heap` )
        ( nurl_println ( string_data . p name ) )
    }
    ~ q ps { = . q n 9 }
    ^ - + k . ( vec_at [App] ps 0 ) n 3
}
