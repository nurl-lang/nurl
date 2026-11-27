// A spawned closure that owns a Vec it captured, moved into its
// environment.
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : ( @ v ) body \ → v { : i n ( vec_len [i] v ) }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
