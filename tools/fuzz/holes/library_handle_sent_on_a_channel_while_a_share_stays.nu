// library_handle_sent_on_a_channel_while_a_share_stays: a library handle sent on a channel (`( chan_send ch a )`) while the sender kept a share of it: the receiving thread and the sender changed one counter with no lock.
// Closed: chan_send checks what it hands over (mem_send_check, h349) and panics on the share left behind.
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | B | runs-clean | h352 | a PNCounter sent on a channel while the sender kept a share: chan_send checks what it hands over and panics
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel PNCounter ) ch ( chan_new [PNCounter] )
    : ( @ v ) body \ → v { ?? ( chan_recv [PNCounter] ch ) { T c → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc c k 1 ) = k + k 1 } } F _ → {} } }
    : PNCounter a ( pncounter_new )
    : PNCounter b ( PNCounter_share a )
    ?? ( thread_spawn body ) { T t → {
            ( chan_send [PNCounter] ch a )
            : ~ i k 0 ~ < k 20000 { ( pncounter_inc b + k 100000 1 ) = k + k 1 }
            ( thread_join t )
        } F _ → {} }
    ^ % ( pncounter_value b ) 256
}
