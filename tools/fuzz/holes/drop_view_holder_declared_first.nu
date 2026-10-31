// drop_view_holder_declared_first: agora #224 — `: ~ W w` declared before the String it is given a view of: with LIFO drops the String goes first (drop_view_holder_declared_first).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted and ran clean only because it dropped in declaration order.
// map: §7.6 | A2 | rejected | - | agora #224: `: ~ W w` declared before the String it is given a view of: with LIFO drops the String goes first
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ W w @ W { `literal` }
    : String s ( string_from `declared after w, so dropped before it` )
    = w @ W { ( string_data s ) }
    ^ 0
}
