// diag_sync_closure_own_handle_plain_vec.nu — a handle synchronises itself
// by what it is made of, not by being a handle (docs/MEMORY.md §6.5; agora
// #639). `Bag` has a drop hook, so it is a handle, and it holds a plain
// Vec: a thread-shared closure that hands its captured struct's Bag, by
// value, to a function that pushes to that Vec grows one buffer from every
// thread that runs it. The control is thread_own_handle_of_sync_parts.nu:
// a handle made of nothing but Arcs over locks and Atomics.

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: Bag { ( Vec i ) v }

@ Bag_drop sink Bag x → v {}

: App { Bag bag i n }

@ grow Bag j i k → v { ( vec_push [i] . j v k ) }

@ main → i {
    : App app @ App { @ Bag { ( vec_new [i] ) } 1 }
    : ( @ v i ) work \ i k → v { ( grow . app bag k ) }
    : ( Arc ( @ v i ) ) shared ( arc_new [( @ v i )] work )
    ^ 0
}
