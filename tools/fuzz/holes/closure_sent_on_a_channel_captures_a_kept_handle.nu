// closure_sent_on_a_channel_captures_a_kept_handle: a closure capturing a PNCounter was sent on a channel to a worker that ran it, while the sender kept changing the counter: the closure's copy of it is the sender's very state, changed by two threads with no lock.
// Closed: a call that keeps a closure beside a handle another thread takes it from (a channel, an Arc, a handle asserted `% Sync`, or one it returns) moves the closure's captures that are not Sync, as a detach does; the sender's use after the send is rejected.
// v0.78.0: accepted; ASan reported heap-use-after-free / double-free in the replica Vec.
// map: §6.5 | A3 | rejected | h340 | a closure capturing a PNCounter sent on a channel while the sender kept changing it: keeping a closure beside a handle another thread takes it from moves its captures that are not Sync
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( @ v i ) f \ i k → v { ( pncounter_inc a k 1 ) }
    : ( Channel ( @ v i ) ) ch ( chan_new [( @ v i )] )
    : ( Channel ( @ v i ) ) ch2 ( Channel_share [( @ v i )] ch )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        ?? ( chan_recv [( @ v i )] ch2 ) {
            T g → { : ~ i k 0 ~ < k 20000 { ( g k ) = k + k 1 } }
            F → {}
        }
    } )
    : b _s ( chan_send [( @ v i )] ch f )
    : ~ i k 0
    ~ < k 20000 { ( pncounter_inc a + k 100000 1 ) = k + k 1 }
    ?? t { T th → { ( thread_join th ) } F _ → {} }
    ^ 0
}
