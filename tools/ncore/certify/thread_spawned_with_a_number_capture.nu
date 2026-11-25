$ `stdlib/std/thread.nu`

@ main → i {
    : i n 41
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
