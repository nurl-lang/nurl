// alias_import_mod.nu — library consumed by alias_import_use.nu.
// When imported with an alias (`$ `...` m`) every top-level @ function
// defined here is renamed to `m__name` by the compiler's import-alias
// pass, so internal calls (ai_double → ai_add) are rewritten together
// with their definitions and stay linked after mangling.

@ ai_add i a i b → i {
    ^ + a b
}

@ ai_mul i a i b → i {
    ^ * a b
}

@ ai_double i x → i {
    ^ ( ai_add x x )
}
