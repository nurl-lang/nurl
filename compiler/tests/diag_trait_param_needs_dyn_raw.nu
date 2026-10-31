// diag_trait_param_needs_dyn_raw.nu — as diag_trait_param_needs_dyn, the callee
// `raw` and the struct two words wide: the IR was valid and the program read
// the struct's second field as the vtable (SEGV; agora #275).

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`

% Speak [T] {
    @ speak T self → i
}

: Dog { i legs }

% Speak Dog {
    @ speak Dog self → i { ^ . self legs }
}

: Two { i a i b }

% Speak Two {
    @ speak Two self → i { ^ + . self a . self b }
}

: Vy { ( Vec i ) v i n }

% Speak Vy {
    @ speak Vy self → i { ^ . self n }
}

raw @ hear sink %Speak s → i { ^ ( speak s ) }
// Calls a raw callee: raw code vouches for what it hands over.
unsafe @ go → i { ^ ( hear @ Vy { ( vec_new [i] ) 3 } ) }

@ main → i {
    ( nurl_println_int ( go ) )
    ^ 0
}
