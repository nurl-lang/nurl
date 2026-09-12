// diag_dynsig_context.nu — an error raised while re-parsing a trait
// method's signature speaks from a SYNTHETIC buffer with no file to
// open. The location stays synthetic (the buffer is a reconstructed,
// Self-substituted signature), so the message has to carry what the
// location cannot: the trait, the method, the Self type, and where the
// fix goes.
//
// The witness here is a literal where a parameter type belongs. It used
// to be the ASCII-arrow mistake, which reached the same machinery
// through the `dyn` path; a trait method header with no arrow is
// rejected at the DECLARATION now — see diag_trait_method_no_arrow.nu —
// so that spelling no longer arrives with a synthetic location at all.
// The decoration this test is about is unchanged, and still the only
// thing standing between the reader and '<…>:1:10'.

% Speaker [T] {
    @ sound T self 42 x → s
}

: Dog {
    i x
}

% Speaker Dog {
    @ sound Dog self i x → s {
        ^ `woof`
    }
}

@ main → i {
    : Dog d @ Dog { 1 }
    : %Speaker obj # % Speaker d
    ( nurl_print ( sound obj ) )
    ^ 0
}
