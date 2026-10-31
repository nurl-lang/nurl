// dyn_inout_method_replaces_what_a_view_reads: a String read out of a trait object, then a method with an `inout` receiver whose impl gives that String a new value: the old one was released, and the view went on reading it — the virtual callee's summaries were the union of the impls' except the replacement summary, so nothing ended the view.
// Closed: the virtual callee's parameters are edges to every impl's in the replacement summary's fixed point (resolve_replaces), as in the mutation summaries'.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §2.10 | A2 | rejected | h365 | a String read out of a trait object, then an inout method whose impl gives it a new value: the virtual callee's replacement summary was not the impls' union, so the view outlived the release; each virtual parameter is an edge to every impl's
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

@ main → i {
    : ~ % Label k ( dyn Label @ Named { ( string_from `the first name, long enough for a heap buffer` ) } )
    : String n ( name k )
    ( rename k )
    ( nurl_println ( string_data n ) )
    ^ 0
}
