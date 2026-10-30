// helper_hands_its_parameter_to_a_dyn_method: as h365, through a helper handing its `inout` trait-object parameter to the method: the helper's summaries were closed before the virtual callee had the impls', so the helper changed nothing as far as its callers knew.
// Closed: the edges from a virtual callee to its impls go into the mutation summaries' fixed point (__dyn_virtual_mut_edges, before resolve_mutation_summaries) and the replacement summary's, so a function that hands a parameter to a `dyn` call does what the impls do to it.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §2.10 | A2 | rejected | h366 | as h365 through a helper handing its inout trait-object parameter on: the helper's summaries closed before the virtual callee had the impls'; the edges go into both fixed points
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
    ( relabel k )
    ( nurl_println ( string_data n ) )
    ^ 0
}
