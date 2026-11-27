// A spawn's result matched with its error arm first; the error is read.
$ `stdlib/std/thread.nu`

@ main → i {
    : i n 7
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { F _ → 1 T t → ( thread_join t ) }
}
