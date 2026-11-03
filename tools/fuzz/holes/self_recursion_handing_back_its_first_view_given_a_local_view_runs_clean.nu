// self_recursion_handing_back_its_first_view_given_a_local_view_runs_clean: a self-recursive function hands back a Vec holding only its first parameter; it passes a view of its own local String down as the second.
// Closed: functions whose walks ask each other's answers (a recursion: a strongly connected component of the parked walks) settle them together, as the least fixed point — each walked quietly from "nothing" with its fellows' latest answers until none grows (__bck_walk_scc). A call of itself no longer answers "may" for every argument.
// main 4f15689: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a self-recursive holder of its first view passes a local's view down as its second
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ collect s text s label i depth → ( Vec s ) {
    ? == depth 0 {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h text )
        ^ h
    } {}
    : String lab ( string_from label )
    : ( Vec s ) r ( collect text ( string_data lab ) - depth 1 )
    ^ r
}

@ main → i {
    : ( Vec s ) r ( collect `root text` `root` 2 )
    ( nurl_println ( vec_at [s] r 0 ) )
    ^ 0
}
