// drop_view_holder_vec_before_source: agora #224 — a W kept in a Vec made before the String it views (drop_view_holder_vec_before_source).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view) is a use of what the view points into, so a source of its views that ends first — reallocated, moved, out of scope, or dropped before it at a return — is refused where it ends (bck_drop_view_diag, bck_ret_drop_check; agora #224).
// main: accepted and ran clean only because it dropped in declaration order.
// map: §7.6 | A2 | rejected | - | agora #224: a W kept in a Vec made before the String it views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ( Vec W ) ws ( vec_new [W] )
    : String s ( string_from `a holder kept in a Vec made before its source` )
    ( vec_push [W] ws @ W { ( string_data s ) } )
    ^ 0
}
