// boxed_option_owner_given_a_lend_beside_a_cursor_runs_clean: `: ~ ?( Box String ) o` with a `: ~` cursor, given a lend out of a Vec and then a fresh value.
// Guard for agora #366: an option of a library handle given a lend beside a cursor runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #366 guard: an option of a Box given a lend beside a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

@ mk → ?( Box String ) { ^ @ ?( Box String ) { T ( box_new [String] ( string_from `a boxed string, long enough for the heap allocation` ) ) } }

@ main → i {
    : ( Vec ? ( Box String ) ) rs ( vec_new [? ( Box String )] )
    ( vec_push [? ( Box String )] rs ( mk ) )
    : ~ ? ( Box String ) o ( mk )
    : ~ ? ( Box String ) c o
    = o ( vec_at [? ( Box String )] rs 0 )
    = o ( mk )
    ^ 0
}
