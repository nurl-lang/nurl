// diag_dyn_inout_replace_ends_views.nu — a method called through a trait
// object does to its arguments what any impl of it may (the virtual
// callee's summaries are the union of the impls'), the replacement summary
// included: an impl that gives its `inout` receiver's String a new value
// releases the old one, so what was read out of the object before ends at
// the call — called directly, or through a helper handing its parameter
// on (h365, h366).
$ `stdlib/core/string.nu`

: Named { String name }

% Label [T] {
    @ rename inout T self → v
    @ name T self → String
}

% Label Named {
    @ rename inout Named c → v { = . c name ( string_from `a different name, long enough for a heap buffer` ) }
    @ name Named c → String { ^ . c name }
}

@ relabel inout %Label o → v { ( rename o ) }

@ main → i {
    : ~ % Label k ( dyn Label @ Named { ( string_from `the first name, long enough for a heap buffer` ) } )
    : String n ( name k )
    ( rename k )
    ( nurl_println ( string_data n ) )
    : String m ( name k )
    ( relabel k )
    ( nurl_println ( string_data m ) )
    ^ 0
}
