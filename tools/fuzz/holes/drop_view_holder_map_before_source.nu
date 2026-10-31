// drop_view_holder_map_before_source: agora #224 — a W kept in a HashMap made before the String it views: with LIFO drops the String goes first (drop_view_holder_map_before_source).
// Closed: the scope-end drop of a binding whose type runs a destructor of the program's own that may read a view (__drop_may_read_view; a library handle by its type arguments) is a use of what the view points into, so a source dropped before it at a return is refused (bck_ret_drop_check; agora #224).
// main: accepted and ran clean only because it dropped in declaration order.
// map: §7.6 | A2 | rejected | - | agora #224: a W kept in a HashMap made before the String it views
$ `stdlib/core/string.nu`
$ `stdlib/std/hashmap.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ( HashMap i W ) m ( map_new [i W] )
    : String s ( string_from `a holder kept in a map made before its source` )
    : ?W _o ( map_set [i W] m 1 @ W { ( string_data s ) } \ i k → i { ^ k } \ i a i b → b { ^ == a b } )
    ^ 0
}
