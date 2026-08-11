// diag_generic_bare_type_use.nu — a generic struct template's bare
// name used as a struct-field type. 'Pair p' emitted '%Pair' — an
// undefined, unsized named type ("loading unsized types is not
// allowed" from the LLVM verifier, far from the source). A generic
// names a family of types; the diagnostic says so and shows the
// parenthesised instantiation form.

: Pair [A B] {
    A first
    B second
}

: Holder { Pair p }

@ main → i {
    ^ 0
}
