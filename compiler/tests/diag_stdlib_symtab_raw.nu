// diag_stdlib_symtab_raw.nu — the standard library's raw symbol table
// (nurl_sym_*) takes the table's address as a plain integer: only unsafe
// code may call it; safe code uses a SymTab.

$ `stdlib/core/symtab.nu`

@ main → i {
    : i t ( nurl_sym_new )
    ^ 0
}
