// A spawn inside a function of the program, its handle joined there.
$ `stdlib/std/thread.nu`

@ run i n → i {
    : ( @ v ) body \ → v { : i m + n 1 }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}

@ main → i { ^ ( run 41 ) }
