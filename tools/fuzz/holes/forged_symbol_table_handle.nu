// forged_symbol_table_handle: safe code passed a made-up number to the standard library's raw symbol table (nurl_sym_get): the table's `i` handle is its address, and the number was read as one.
// Closed: the library's raw `nurl_sym_*` table is `unsafe` only for programs; a program holds a SymTab, which it cannot make up.
// main's compiler: AddressSanitizer: SEGV on a wild read.
// map: §6.4 | B | rejected | h252 | made-up integer passed as raw symbol-table handle to nurl_sym_get
$ `stdlib/core/symtab.nu`

@ main → i {
    : s v ( nurl_sym_get 123456789 `key` )
    ( nurl_println v )
    ^ 0
}
