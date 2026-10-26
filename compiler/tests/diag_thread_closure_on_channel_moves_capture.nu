// diag_thread_closure_on_channel_moves_capture.nu
// A closure sent on a channel runs on the thread that receives it. Its
// copy of a captured PNCounter is the sender's very state, so the send
// takes the capture along, as a thread's closure does: the sender may
// not change the counter afterwards (h340).

$ `stdlib/std/channel.nu`
$ `stdlib/dist/crdt.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( @ v i ) f \ i k → v { ( pncounter_inc a k 1 ) }
    : ( Channel ( @ v i ) ) jobs ( chan_new [( @ v i )] )
    : b _sent ( chan_send [( @ v i )] jobs f )
    ( pncounter_inc a 2 1 )
    ^ 0
}
