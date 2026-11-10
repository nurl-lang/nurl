// bare_view_forwarded_in_a_join_kept_while_a_sibling_field_is_cleared_runs_clean: agora #471 — `^ ? c ( string_data ( vec_at [String] . r items 0 ) ) ( first d )`; the caller clears `. r name`, then reads the answer (the shape the fix must keep)
// Refused since agora #487: the join's arm is a view of `. r items`, and a bare `s` answer is per parameter, so clearing `. r name` ends it, as it ends the direct `^ ( string_data ( vec_at [String] . r items 0 ) )` on main. Accepted on main only because the join's arms lent nothing at all (the hole #487 closes). Path-precise answers (`r.items`) would accept it again: agora #572.
// main 9d2e7cd: runs clean (safe: the view is of `. r items`, and `. r name` is cleared).
// map: §2.10 | A2 | rejected | - | agora #471/#487: a forwarded bare view in a join, kept while a sibling field is cleared (refused per parameter until path-precise answers, #572)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String name ( Vec String ) items }

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ ``
}

@ pick R r ( Vec String ) d b c → s {
    ^ ? c ( string_data ( vec_at [String] . r items 0 ) ) ( first d )
}

@ main → i {
    : ( Vec String ) d ( vec_new [String] )
    ( vec_push [String] d ( string_from `a default, long enough for a heap buffer` ) )
    : R r @ R { ( string_from `a name, long enough for a heap buffer` ) ( vec_new [String] ) }
    ( vec_push [String] . r items ( string_from `an item, long enough for a heap buffer` ) )
    : s v ( pick r d T )
    ( string_clear . r name )
    ( nurl_println v )
    ^ 0
}
