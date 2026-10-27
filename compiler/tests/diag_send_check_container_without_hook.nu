// A library handle whose contents may hold a handle whose copies are one
// state crosses to another thread only if the crossing check can see
// inside it: its module defines `S_sendck` beside its drop, handing each
// value it holds to `( mem_send_check [T] x what )` (docs/MEMORY.md §6.5).
// A `Bag` of PNCounters with no `Bag_sendck` cannot be checked.
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Bag [T] { ( Vec T ) items }

@ Bag_drop [T] sink ( Bag T ) b → v {}

@ bag_new [T] → ( Bag T ) { ^ @ ( Bag T ) { ( vec_new [T] ) } }

@ main → i {
    : ( Bag PNCounter ) b ( bag_new [PNCounter] )
    : ( @ v ) body \ → v { ( nurl_println_int ( vec_len [PNCounter] . b items ) ) }
    ?? ( thread_spawn body ) { T t → { ( thread_join t ) } F _ → {} }
    ^ 0
}
