// par_map_index_closure_changing_its_capture_is_refused: `( par_map_index [i] 20000 8 f )` with `f` pushing to a captured Vec
// Closed: agora #713, a parameter a detach in a loop captures is run on several threads, so the closure is held to Sync and the Sync-closure rule.
// main dc7f5adf: accepted (ASan: attempting double-free, in a worker thread).
// map: §6.5 | A3 | rejected | - | agora #713: par_map_index runs f on several threads, so f may not change what it captured
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/par.nu`

@ main → i {
    : ( Vec i ) seen ( vec_new [i] )
    : ( @ i i ) f \ i k → i { ( vec_push [i] seen k ) ^ k }
    : ( Vec i ) out ( par_map_index [i] 20000 8 f )
    ^ 0
}
