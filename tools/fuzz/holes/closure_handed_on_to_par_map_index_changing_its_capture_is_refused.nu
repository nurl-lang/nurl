// closure_handed_on_to_par_map_index_changing_its_capture_is_refused: a helper handing its closure parameter on to par_map_index, given a closure that pushes to a captured Vec
// Closed: agora #713, the requirement follows the parameter through the forwarder (`__sync_req_params`).
// main dc7f5adf: accepted (ASan: attempting double-free, in a worker thread).
// map: §6.5 | A3 | rejected | - | agora #713: a closure handed on to par_map_index is run on several threads, so it may not change what it captured
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/par.nu`

@ squares ( @ i i ) g → ( Vec i ) { ^ ( par_map_index [i] 2000 8 g ) }

@ main → i {
    : ( Vec i ) seen ( vec_new [i] )
    : ( Vec i ) out ( squares \ i k → i { ( vec_push [i] seen k ) ^ * k k } )
    ^ 0
}
