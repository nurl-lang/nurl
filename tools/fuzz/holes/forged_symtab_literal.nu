// forged_symtab_literal: safe code built a SymTab around a made-up number (`@ SymTab { 123456789 }`): its drop freed whatever was at that address.
// Closed: SymTab's field is the table's address (`*u`), which seals it — only the library makes one (symtab_new) — and with a `% Drop` and no clone it moves, so no two SymTabs release one table.
// main's compiler: AddressSanitizer: attempting free on a wild address.
// map: §6.2 | B | rejected | h253 | SymTab struct literal forged around a made-up address; drop frees it
$ `stdlib/core/symtab.nu`

@ main → i {
    : SymTab a @ SymTab { # *u 123456789 }
    ^ 0
}
