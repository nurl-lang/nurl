// view_copied_out_of_a_loop_element_of_views_kept_past_the_container_runs_clean: agora #471 — a view element of `~ e vvs { ~ v e { … } }` over a `( Vec ( Vec s ) )` pushed into an outer holder, kept past `vvs`; the String it views lives (the shape the fix must keep)
// Closed: only an owner's own storage is a part of the container: a view element is a copy of what it points into (Family G), so a copy of it holds the String, not the container (agora #471).
// main 0c11a93: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: a view element copied out of a loop over a Vec of views, kept past the container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String line ( string_from `a line of text that outlives every container here` )
    : ~ ( Vec s ) ws ( vec_new [s] )
    {
        : ( Vec ( Vec s ) ) vvs ( vec_new [( Vec s )] )
        : ( Vec s ) inner ( vec_new [s] )
        ( vec_push [s] inner ( string_data line ) )
        ( vec_push [( Vec s )] vvs inner )
        ~ e vvs { ~ v e { ( vec_push [s] ws v ) } }
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
