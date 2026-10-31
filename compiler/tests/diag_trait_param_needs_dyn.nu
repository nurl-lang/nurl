// diag_trait_param_needs_dyn.nu — a struct passed where a trait object (`%Speak`)
// is declared is refused, and the message names `( dyn Speak value )`. Before,
// the function's whole parameter roster went unrecorded and clang stopped on
// invalid IR (agora #275).

$ `stdlib/core/io.nu`

% Speak [T] {
    @ speak T self → i
}

: Dog { i legs }

% Speak Dog {
    @ speak Dog self → i { ^ . self legs }
}

@ hear %Speak s → i { ^ ( speak s ) }

@ main → i {
    ( nurl_print_int ( hear @ Dog { 4 } ) )
    ( nurl_print `\n` )
    ^ 0
}
