// trait_assoc_import.nu
// A trait with an associated type and a default method, defined in an imported
// module and implemented here. Regresses the cross-import default-method
// double-emission root cause and associated-type substitution through `$`.
$ `compiler/tests/trait_assoc_import_mod.nu`

: IB { i v }

% Boxed IB {
    type Elem i
    @ unwrap IB self → i { ^ . self v }
    // `first` defaulted across the import → @ first__IB IB self i d → i
}

@ main → i {
    : IB a @ IB { 8 }
    : i r ( first a 0 )      // → 8 via the imported default, dispatching to unwrap##IB
    ( nurl_print `r: ` )
    ( nurl_print ( nurl_str_int r ) )
    ( nurl_print `\n` )
    ^ ? == r 8 0 1
}
