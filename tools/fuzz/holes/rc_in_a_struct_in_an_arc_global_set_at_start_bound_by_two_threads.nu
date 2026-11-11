// rc_in_a_struct_in_an_arc_global_set_at_start_bound_by_two_threads: a global set at start holding the standard library's `( Arc Holder )`, where `Holder` has an `Rc` field. Every thread reads the one payload; two of them bind the `Rc` out of it — a share each, counted on a count that is not atomic. An `Arc` that crosses to a thread is refused for what its payload holds; the same `Arc` as a global reached every thread unasked.
// main: accepted — the rule read the type's outermost name (`Arc`) and never the payload; two threads race on the Rc's count (a torn count frees the block early or never: ASan sees it only when the race lands).
// map: §6.5 | A3 | rejected | - | an ( Arc Holder ) global set at start whose payload holds an Rc, bound out by two threads: the payload must be Sync as any shared Arc's (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Holder { ( Rc i ) r }

@ make → ( Arc Holder ) { ^ ( arc_new [Holder] @ Holder { ( rc_new [i] 5 ) } ) }

: ( Arc Holder ) g_one ( make )

@ churn i n → i {
    : ~ i k 0
    : ~ i seen 0
    ~ < k n {
        : ~ i j 0
        ~ < j 64 {
            : Holder h ( arc_get [Holder] g_one )
            : ( Rc i ) mine . h r
            = seen + seen ( rc_strong [i] mine )
            = j + j 1
        }
        = k + k 1
    }
    ^ seen
}

@ main → i {
    ?? ( thread_spawn \ → v { ( churn 20000 ) } ) {
        T t → { ( churn 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
