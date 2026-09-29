// recover_extent_roots.nu — the writer keeps journal registrations only in
// functions that may run inside a recover extent: those reached from the
// closure a `recover` call is handed, through direct calls and through
// indirect calls of the called signature. Here the panicking frame is
// reached only through a closure the extent calls indirectly, and once
// through a wrapper that hands its own closure parameter to recover (the
// closure is not built at the call site: every address-taken function
// counts). Run under LSan it is leak-clean: every String / Vec the skipped
// frames owned is dropped by the unwind.
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Reached only through the handler closure.
@ build_then_panic i n → String {
    : String s ( string_from `owned-by-a-skipped-frame` )
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `element` ) )
    ? > n 0 { ( panic `boom` ) } {}
    ^ s
}

@ run_handler ( @ String i ) h i n → i {
    : String r ( h n )
    ^ ( string_len r )
}

// Hands its own closure parameter to recover.
@ guarded ( @ v ) f → i {
    ?? ( recover f ) { T _ → { ^ 0 } F e → { ^ 1 } }
}

@ main → i {
    : ( @ String i ) h \ i n → String { ^ ( build_then_panic n ) }
    ?? ( recover \ → v { ( nurl_print_int ( run_handler h 1 ) ) } ) {
        T _ → { ( nurl_print `completed\n` ) }
        F e → { ( nurl_print `recovered: ` ) ( nurl_print ( string_data . e msg ) ) ( nurl_print `\n` ) }
    }
    ?? ( recover \ → v { ( nurl_print_int ( run_handler h 0 ) ) ( nurl_print `\n` ) } ) {
        T _ → { ( nurl_print `completed\n` ) }
        F e → { ( nurl_print `recovered\n` ) }
    }
    ( nurl_print_int ( guarded \ → v { ( nurl_print_int ( run_handler h 1 ) ) } ) ) ( nurl_print `\n` )
    ^ 0
}
