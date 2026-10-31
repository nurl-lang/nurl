// send_asserted_by_safe_code: a safe module asserted `% Send` on a struct holding an Rc and sent it to a thread, which cloned and dropped the Rc while main did the same: two threads on one non-atomic count.
// Closed: a positive marker stops the derivation at the type, so outside the standard library it is an unchecked promise and is written `unsafe % Send Wrapper {}` (grammar v2.11, docs/MEMORY.md §3); `% Send` alone is an error, and `nurlc --unsafe-report` lists the `unsafe` one.
// v0.76.0: accepted; the count drifted under the race and the Rc was freed while both threads still held it (AddressSanitizer: heap-use-after-free, or a double free).
// map: §3 | B | rejected | h318 | safe code asserted % Send over an Rc and raced its count from two threads; a positive marker is now unsafe % Send (heap-use-after-free)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/marker.nu`
$ `stdlib/core/vec.nu`

: Wrapper { ( Rc i ) r }

% Send Wrapper {}

@ main → i {
    : ( Rc i ) a ( rc_new [i] 1 )
    : Wrapper w @ Wrapper { ( rc_clone [i] a ) }
    : ( @ v ) body \ → v {
        : ~ i k 0
        : ( Vec ( Rc i ) ) keep ( vec_new [( Rc i )] )
        ~ < k 3000000 { ( vec_push [( Rc i )] keep ( rc_clone [i] . w r ) ) ? == 0 % k 64 { ( vec_clear [( Rc i )] keep ) } {} = k + k 1 }
    }
    ?? ( thread_spawn body ) {
        T t → {
            : ~ i k 0
            : ( Vec ( Rc i ) ) keep2 ( vec_new [( Rc i )] )
            ~ < k 3000000 { ( vec_push [( Rc i )] keep2 ( rc_clone [i] a ) ) ? == 0 % k 64 { ( vec_clear [( Rc i )] keep2 ) } {} = k + k 1 }
            ( vec_clear [( Rc i )] keep2 )
            ( thread_join t )
        }
        F _ → {}
    }
    ^ ( rc_get [i] a )
}
