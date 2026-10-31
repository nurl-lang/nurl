// race_shared_vec: two threads mutate one Vec captured by both closures.
// map: §6.5 | A3 | rejected | h09 | two threads push into one Vec captured by both closures; A3.0: the Vec moves to one thread, so no two threads reach it
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ( @ v ) w \ → v { : ~ i k 0 ~ < k 100000 { ( vec_push [i] xs k ) = k + k 1 } }
    : !Thread ThreadErr t1 ( thread_spawn w )
    : !Thread ThreadErr t2 ( thread_spawn w )
    ?? t1 { T t → { : i _a ( thread_join t ) } F _ → {} }
    ?? t2 { T t → { : i _b ( thread_join t ) } F _ → {} }
    ( nurl_println_int ( vec_len [i] xs ) )
    ^ 0
}
