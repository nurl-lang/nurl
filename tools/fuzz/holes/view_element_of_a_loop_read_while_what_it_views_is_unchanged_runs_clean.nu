// view_element_of_a_loop_read_while_what_it_views_is_unchanged_runs_clean: agora #492 — a loop over a `( Vec s )` that reads each view while what they view is unchanged; the source grows after the loop
// Control for agora #492: the element is refused only once what it views changed.
// map: §2.5 | A2 | runs-clean | - | agora #492: a loop over a `( Vec s )` that reads each view while what they view is unchanged; the source grows after the loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String line ( string_from `a line long enough for a heap buffer` )
    : ( Vec s ) ws ( vec_new [s] )
    ( vec_push [s] ws ( string_data line ) )
    ( vec_push [s] ws `lit` )
    ~ v ws { ( nurl_println v ) }
    ( string_push_str line ` tail` )
    ^ 0
}
