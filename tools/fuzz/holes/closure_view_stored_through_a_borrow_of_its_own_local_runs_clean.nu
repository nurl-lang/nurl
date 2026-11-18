// closure_view_stored_through_a_borrow_of_its_own_local_runs_clean: the guard of view_stored_through_a_borrow_of_a_closure_capture: inside a closure, a view of a closure local stored through `( id mine )`, a borrow of another closure local, read while both live
// Closed (agora #395): the holder is the closure's own local, or what is stored owns its data: no capture is given a view, nothing is refused.
// main 6005efcb: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #395: a view stored through a borrow of a closure's own local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ id ( Vec s ) x → ( Vec s ) { ^ x }

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    : ( @ v ) f \ → v {
        : String loc ( string_from `a heap string the closure reads while it lives` )
        : ( Vec s ) mine ( vec_new [s] )
        : ( Vec s ) w ( id mine )
        ( vec_push [s] w ( string_data loc ) )
        ( nurl_println ( vec_at [s] mine 0 ) )
        // (vs is captured, so the walk has captures to ask of: the store
        // into mine goes through the holder check and is not refused)
        ( nurl_print_int ( vec_len [s] vs ) )
    }
    ( f )
    ( nurl_print_int ( vec_len [s] vs ) )
    ^ 0
}
