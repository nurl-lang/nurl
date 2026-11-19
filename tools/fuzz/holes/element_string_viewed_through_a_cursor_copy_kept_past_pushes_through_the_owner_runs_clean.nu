// element_string_viewed_through_a_cursor_copy_kept_past_pushes_through_the_owner_runs_clean: AGORA-428 guard — `: ~ w vs`, a view of an element's String through w, then pushes through vs: the String's own buffer stays where it is, accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-428 guard: a view of an element through a handle copy outlives the owner's growth
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element long enough for its own buffer on the heap` ) )
    : ~ ( Vec String ) w vs
    : s e ( string_data ( vec_at [String] w 0 ) )
    : ~ i k 0
    ~ < k 1000 { ( vec_push [String] vs ( string_from `x` ) ) = k + k 1 }
    ( nurl_println e )
    ^ 0
}
