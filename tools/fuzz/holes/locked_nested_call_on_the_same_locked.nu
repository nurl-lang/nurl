// locked_nested_call_on_the_same_locked: a locked_with nested in another's closure on the same Locked clears the Vec the outer closure holds a view of, then the outer reads the view.
// Closed: a Locked's lock is a check-out with a holder (stdlib/runtime_locked.c); its holder asking for it again panics (the model's Step.waitPanic), so the inner closure never runs. Recovered, the outer one reads its view intact.
// v0.90.0: the closure ran with a default pthread mutex held. Relocked by the thread that held it: a hang on glibc; on FreeBSD (an error-checking default) EDEADLK went unread and the inner closure freed the buffer under the outer one's view (heap-use-after-free).
// map: §6.5 | A3 | runs-clean | - | agora #455: a nested locked_* on the same Locked panics instead of relocking the mutex its thread holds
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/panic.nu`

@ main → i {
    : ( Vec i ) seed ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] seed k ) = k + k 1 }
    : ( Locked ( Vec i ) ) q ( locked_new [( Vec i )] seed )
    : ( Locked ( Vec i ) ) q2 ( Locked_share [( Vec i )] q )
    : ~ i sum 0
    ( locked_with [( Vec i )] q \ ( Vec i ) xs → v {
        : !v PanicInfo pr ( recover \ → v {
            ( locked_with [( Vec i )] q2 \ ( Vec i ) ys → v { ( vec_clear [i] ys ) ( vec_shrink_to_fit [i] ys ) } )
        } )
        : ~ i j 0
        ~ < j ( vec_len [i] xs ) { = sum + sum ( vec_at [i] xs j ) = j + j 1 }
    } )
    ? != sum 2016 { ( nurl_panic `the outer closure lost its value` ) } {}
    ^ 0
}
