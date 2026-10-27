// A thread's closure that captures a binding read out of a library handle
// field takes the field — and the struct — along: the spawner's struct
// would otherwise keep a second owner of the counter (agora #121, h356).
$ `stdlib/dist/crdt.nu`
$ `stdlib/std/thread.nu`

: Holder { PNCounter c }

@ main → i {
    : Holder h @ Holder { ( pncounter_new ) }
    : PNCounter x . h c
    : ( @ v ) body \ → v { ( pncounter_inc x 1 1 ) }
    ?? ( thread_spawn body ) { T t → { ( pncounter_inc . h c 2 1 ) ( thread_join t ) } F _ → {} }
    ^ 0
}
