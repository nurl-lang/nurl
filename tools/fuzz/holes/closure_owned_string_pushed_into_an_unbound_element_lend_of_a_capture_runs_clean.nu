// closure_owned_string_pushed_into_an_unbound_element_lend_of_a_capture_runs_clean: the guard of closure_view_pushed_into_an_unbound_element_lend_of_a_capture: inside a closure, an owned String pushed into `( vec_at vv 0 )` of a capture
// Closed (agora #395): the holder is the closure's own local, or what is stored owns its data: no capture is given a view, nothing is refused.
// main 6005efcb: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #395: an owned value pushed into a capture's element through an unbound call
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    : ( @ v ) f \ → v {
        ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an owned string the capture's element keeps` ) )
    }
    ( f )
    ( nurl_println ( string_data ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 ) ) )
    ^ 0
}
