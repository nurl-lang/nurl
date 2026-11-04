// views_of_nested_loop_elements_kept_past_a_later_binding_of_the_outer_elements_name_runs_clean: agora #471 — views collected by `~ e vv { ~ x e { … } }`, then `: i e 7` — a later binding of the outer element's name — then the views are read (the shape the fix must keep)
// Closed: a `~` loop's element is gone with its loop: the views of it let go of its name for the container's element (`__bck_fe_retire`), so a later binding of the name ends none of them (agora #471's adversarial pass).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: views of nested loop elements, kept past a later binding of the outer element's name
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `an inner string of vv, never changed` ) )
    ( vec_push [( Vec String )] vv r0 )
    : ( Vec s ) ws ( vec_new [s] )
    ~ e vv { ~ x e { ( vec_push [s] ws ( string_data x ) ) } }
    : i e 7
    ( nurl_println_int e )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
