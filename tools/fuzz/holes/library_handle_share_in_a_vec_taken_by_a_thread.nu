// library_handle_share_in_a_vec_taken_by_a_thread: a share of a library handle pushed into a Vec (`( vec_push v ( PNCounter_share a ) )`) went to a thread with the Vec while the spawner kept `a`: one counter changed by two threads with no lock.
// Closed: the crossing check walks a Vec's elements (and a HashMap's, a Deque's, a BTree's, a Set's, a Box's: their `S_sendck` hooks) and panics on the element's second owner (mem_send_check, h349).
// v0.78.0: accepted; ASan reported double-free in the replica Vec.
// map: §6.5 | B | runs-clean | h351 | a share pushed into a Vec that went to a thread: the crossing check walks a Vec's elements (a container's through its S_sendck hook) and panics
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : PNCounter a ( pncounter_new )
    : ( Vec PNCounter ) v ( vec_new [PNCounter] )
    ( vec_push [PNCounter] v ( PNCounter_share a ) )
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 20000 { ?? ( vec_get [PNCounter] v 0 ) { T c → { ( pncounter_inc c k 1 ) } F → {} } = k + k 1 } }
    ?? ( thread_spawn body ) { T t → { : ~ i k 0 ~ < k 20000 { ( pncounter_inc a + k 100000 1 ) = k + k 1 } ( thread_join t ) } F _ → {} }
    ^ % ( pncounter_value a ) 256
}
