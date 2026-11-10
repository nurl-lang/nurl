// loop_element_pushed_into_another_vec_a_view_of_it_read_after_runs_clean: agora #490 — `~ x t { ( vec_push u x ) }` copies the element; a view of t's element taken before is read after
// Control for agora #490: an element stored into another owner is copied, its slot as it was; only a move out ends the borrows.
// map: §2.5 | A2 | runs-clean | - | agora #490: `~ x t { ( vec_push u x ) }` copies the element; a view of t's element taken before is read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `first string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `second string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `third string long enough for a heap buffer here` ) )
    : ( Vec String ) u ( vec_new [String] )
    : s first ( string_data ( vec_at [String] t 0 ) )
    ~ x t { ( vec_push [String] u x ) }
    ( nurl_println first )
    ( nurl_println_int ( vec_len [String] u ) )
    ^ 0
}
