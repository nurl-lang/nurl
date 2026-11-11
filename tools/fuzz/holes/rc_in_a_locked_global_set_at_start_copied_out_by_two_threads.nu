// rc_in_a_locked_global_set_at_start_copied_out_by_two_threads: a global set at start is read by every thread, so what it holds is shared between them as an `Arc`'s payload is. This one is the standard library's `( Locked ( Rc i ) )`: two threads copy the `Rc` out under the lock (`locked_get`) and drop their copies outside it, and an `Rc`'s count is not atomic. A `Locked` hands its value to one thread at a time, so the value must be Send — asked of a `Locked` that crosses to a thread, and now of one every thread reaches as a global.
// main: accepted — the rule read the type's outermost name (`Locked`) and never what it holds; the count is torn and the block freed under a reader (ASan: heap-use-after-free, when the race lands).
// map: §6.5 | A3 | rejected | - | a ( Locked ( Rc i ) ) global set at start, the Rc copied out by two threads: the global's type is asked what a value shared between threads is asked (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

@ make → ( Locked ( Rc i ) ) { ^ ( locked_new [( Rc i )] ( rc_new [i] 5 ) ) }

: ( Locked ( Rc i ) ) g_one ( make )

@ churn i n → i {
    : ~ i k 0
    : ~ i seen 0
    ~ < k n {
        : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
        : ~ i j 0
        ~ < j 64 { ( vec_push [( Rc i )] cs ( locked_get [( Rc i )] g_one ) ) = j + j 1 }
        = seen + seen ( vec_len [( Rc i )] cs )
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
