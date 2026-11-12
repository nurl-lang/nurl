// par_map_index_closure_only_reading_its_capture_runs_clean: `( par_map_index [i] 2000 8 f )` with `f` only reading a captured Vec's length
// Guard for agora #713's fix: a closure several threads run may read what it captured.
// main dc7f5adf: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #713 guard: par_map_index with an f that only reads its capture stays accepted
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/par.nu`

@ main → i {
    : ( Vec i ) seen ( vec_new [i] )
    ( vec_push [i] seen 5 )
    : ( @ i i ) f \ i k → i { ^ + k ( vec_len [i] seen ) }
    : ( Vec i ) out ( par_map_index [i] 2000 8 f )
    ( nurl_println_int ( vec_len [i] out ) )
    ^ 0
}
