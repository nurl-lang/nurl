// diag_generic_struct_unclosed.nu — a generic struct template whose
// '{' is never closed. collect_fn_body's depth loop had no EOF guard,
// so `nurlc file.nu` HUNG forever on this shape (found by the
// drop-close-brace mutation across every generic-using corpus
// program). Now a hard error anchored at the opening brace.

: Pair [A B] {
    A first
    B second

    @ main → i {
        ^ 0
    }
