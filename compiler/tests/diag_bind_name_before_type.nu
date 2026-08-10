// diag_bind_name_before_type.nu — ': name type value', the order Go and
// Rust use. NURL puts the type first.
//
// The type keyword reached gen_ident and came back as "use of undefined
// identifier 'i'" — naming the token and then calling it the wrong
// thing, which sends the reader looking for a binding that was never the
// problem. A bare type keyword yields no value, so it can never open a
// legitimate initialiser; in the inference branch it is this swap and
// nothing else.
@ main → i {
    : n i 0
    ^ n
}
