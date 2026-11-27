// A spawned closure sends a String on a channel share it owns; main
// receives it.
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel String ) ch ( chan_new [String] )
    : ( Channel String ) tx ( Channel_share [String] ch )
    : ( @ v ) body \ → v { ( chan_send [String] tx ( string_from `a message from the thread` ) ) }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    : i j ?? r { T t → ( thread_join t ) F _ → 1 }
    : ?String got ( chan_recv [String] ch )
    ( chan_close [String] ch )
    ^ j
}
