// An Arc whose payload holds a library handle with closures in its state
// (a JobNode and its handlers) is not frozen by that alone: each closure
// got into the node through a call the store check vetted — it can lead
// nowhere back to the node — so a cycle through it would have to pass
// through the node, and there is none. The payload may be updated in
// place (arc_ptr). A handler capturing the Arc itself is still refused
// at its job_register (thread_shared tests).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`
$ `stdlib/net/transport.nu`

: Bundle { JobNode jn i epoch }

unsafe @ main → i {
    : JobNode jn ( job_node_new ( transport_none ) ( ring_new ) ( vec_new [u] ) 1 )
    ( job_register jn 1 \ ( Vec u ) p → ( Vec u ) { ^ ( vec_new [u] ) } )
    : ( Arc Bundle ) a ( arc_new [Bundle] @ Bundle { jn 0 } )
    : *Bundle b ( arc_ptr [Bundle] a )
    = . b epoch + . b epoch 1
    ( nurl_println_int . b epoch )
    ^ 0
}
