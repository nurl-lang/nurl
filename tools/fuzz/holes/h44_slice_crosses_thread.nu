// H44: a thread closure captures a Slice while the spawning thread frees the Vec.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : ( Slice i ) s ( slice_from_vec [i] xs )
    : !Thread ThreadErr t ( thread_spawn \ → v { ( sleep_ms 50 ) ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} } } )
    ( vec_free [i] xs )
    ?? t { T h → { ( thread_join h ) } F e → {} }
    ^ 0
}
