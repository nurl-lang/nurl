// Two closure codes, each spawned once and joined: two spawn wrappers.
$ `stdlib/std/thread.nu`

@ main → i {
    : i a 1
    : ( @ v ) one \ → v { : i x + a 1 }
    : ( @ v ) two \ → v { : i y + a 2 }
    : !Thread ThreadErr r ( thread_spawn_owned one )
    : !Thread ThreadErr q ( thread_spawn_owned two )
    : i j ?? r { T t → ( thread_join t ) F _ → 1 }
    : i k ?? q { T t → ( thread_join t ) F _ → 1 }
    ^ + j k
}
