// view_of_a_field_containers_loop_element_kept_while_another_field_is_replaced_runs_clean: agora #471 — `~ x . r xs { ( vec_push [s] ws ( string_data x ) ) }`, then `= . r name …`, another field; `ws` read after (the shape the fix must keep)
// Closed: the element is a part of the path the loop iterates (`. r xs`), not of all of `r`: a sibling field replaced ends nothing it views (agora #471).
// main 0c11a93: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a view of the element of a loop over a field, read after a sibling field was replaced
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { ( Vec String ) xs String name }

@ main → i {
    : ( Vec s ) ws ( vec_new [s] )
    : ~ R r @ R { ( vec_new [String] ) ( string_from `the name` ) }
    ( vec_push [String] . r xs ( string_from `a string long enough for a heap buffer here` ) )
    ~ x . r xs { ( vec_push [s] ws ( string_data x ) ) }
    = . r name ( string_from `another name` )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
