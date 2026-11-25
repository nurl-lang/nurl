$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

// `: ( Channel i ) tx ch` moves the handle (one owner): `ch` is dead after
// it. A translation that read the alias as a new share would certify this.
@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    : ( Channel i ) tx ch
    : ( @ v ) body \ → v { ( chan_send [i] tx 41 ) }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    : i j ?? r { T t → ( thread_join t ) F _ → 1 }
    : ?i got ( chan_recv [i] ch )
    ^ ?? got { T v → + v j F → 0 }
}
