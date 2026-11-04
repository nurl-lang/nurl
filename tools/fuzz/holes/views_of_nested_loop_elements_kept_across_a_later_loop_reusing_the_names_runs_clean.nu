// views_of_nested_loop_elements_kept_across_a_later_loop_reusing_the_names_runs_clean: agora #471 — views collected by `~ e vv { ~ x e { … } }`; a later `~ e other { ~ y e { ( string_push_str y … ) } }` over an unrelated Vec reuses the name; the views are read (the shape the fix must keep)
// Closed: the first loop's element is gone with its loop (`__bck_fe_retire`): a change through the later loop's element reaches `other`'s elements, not the views of `vv`'s (agora #471's adversarial pass).
// main 9d2e7cd: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #471: views of nested loop elements, kept across a later loop that reuses the names and changes another Vec's elements
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) r0 ( vec_new [String] )
    ( vec_push [String] r0 ( string_from `an inner string of vv, never changed` ) )
    ( vec_push [( Vec String )] vv r0 )
    : ( Vec ( Vec String ) ) other ( vec_new [( Vec String )] )
    : ( Vec s ) ws ( vec_new [s] )
    ~ e vv { ~ x e { ( vec_push [s] ws ( string_data x ) ) } }
    ~ e other { ~ y e { ( string_push_str y `, grown` ) } }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}
