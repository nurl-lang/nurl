// diag_let_type_name_as_binding.nu — the one inferred-binding shape the
// grammar cannot take: a first word that NAMES A TYPE.
//
// §5.1: "an identifier that names a registered type is taken as the type
// annotation, otherwise the plain-IDENT form is type-inferred". `: n 5`
// rebinds a value `n` (let_infer_rebind.nu); `: P 5` with a struct `P`
// is a binding OF type P whose name is missing. The message names that
// rule — the writer meant P as a name, and "expected a binding name"
// alone does not say why P was not one.
: P { i a }

@ main → i {
    : P 5
    ^ 0
}
