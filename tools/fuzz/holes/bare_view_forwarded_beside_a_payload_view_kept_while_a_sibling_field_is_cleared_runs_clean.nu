// bare_view_forwarded_beside_a_payload_view_kept_while_a_sibling_field_is_cleared_runs_clean: agora #471 — a helper hands back either a view of a `vec_get` payload of `. r items` or `( first d )`, a forwarded loop-element view; the caller clears `. r name`, then reads the answer (the shape the fix must keep)
// Closed: the forwarded answer marks only the sources its callee answered `2` for (`d`), not the payload view beside it, so a sibling field cleared ends nothing the answer depends on (agora #471).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a forwarded bare view beside a payload view, kept while a sibling field is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String name ( Vec String ) items }

@ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ ``
}

@ pick R r ( Vec String ) d → s {
    ?? ( vec_get [String] . r items 0 ) { T e → { ^ ? > ( string_len e ) 0 ( string_data e ) ( first d ) } F _ → {} }
    ^ ( first d )
}

@ main → i {
    : ( Vec String ) d ( vec_new [String] )
    ( vec_push [String] d ( string_from `a default, long enough for a heap buffer` ) )
    : R r @ R { ( string_from `a name, long enough for a heap buffer` ) ( vec_new [String] ) }
    ( vec_push [String] . r items ( string_from `an item, long enough for a heap buffer` ) )
    : s v ( pick r d )
    ( string_clear . r name )
    ( nurl_println v )
    ^ 0
}
