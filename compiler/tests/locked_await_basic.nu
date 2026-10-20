// locked_await_basic.nu — std/thread.nu locked_await, a monitor's wait.
//
// A work queue in a Locked: four consumer threads wait in locked_await
// until an item or the close flag is there; the producer pushes 10000
// items with locked_update, which wakes the waiters. Every item is taken
// exactly once (the sum), and every consumer leaves once the queue is
// closed and empty (the joins return). A waiter whose run hands back
// nothing does not hold the lock while it sleeps: the producer gets in.
// Also: a loop `~ T` that only returns (no break) in one function next to
// a function whose loop breaks — the infinite-loop verdict is per loop.

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`

: Q { ( Vec i ) items b closed }

@ first_over ( Vec i ) xs i lim → i {
    : ~ i k 0
    ~ T {
        ? >= k ( vec_len [i] xs ) { break } {}
        ? > ( vec_at [i] xs k ) lim { break } {}
        = k + k 1
    }
    ^ k
}

@ index_of ( Vec i ) xs i x → i {
    : ~ i k 0
    ~ T {
        ? >= k ( vec_len [i] xs ) { ^ -1 } {}
        ? == ( vec_at [i] xs k ) x { ^ k } {}
        = k + k 1
    }
}

@ main → i {
    : ( Locked Q ) q ( locked_new [Q] @ Q { ( vec_new [i] ) F } )
    : Atomic sum ( atomic_new 0 )
    : Atomic taken ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ b going T
            ~ going {
                : i x ( locked_await [Q i] q \ inout Q s → ?i {
                    ?? ( vec_pop [i] . s items ) { T it → { ^ @ ?i { T it } } F → {} }
                    ? . s closed { ^ @ ?i { T -1 } } {}
                    ^ @ ?i { F 0 }
                } )
                ? < x 0 { = going F } { ( atomic_add sum x ) ( atomic_add taken 1 ) }
            }
        } )
        ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    : ~ i k 1
    ~ <= k 10000 {
        : i item k
        ( locked_update [Q] q \ inout Q s → v { ( vec_push [i] . s items item ) } )
        = k + k 1
    }
    ( locked_update [Q] q \ inout Q s → v { = . s closed T } )
    ~ th ts { ( thread_join th ) }
    ( nurl_print `taken: ` ) ( nurl_println_int ( atomic_load taken ) )
    ( nurl_print `sum:   ` ) ( nurl_println_int ( atomic_load sum ) )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 3 ) ( vec_push [i] xs 9 ) ( vec_push [i] xs 4 )
    ( nurl_print `first over 5: ` ) ( nurl_println_int ( first_over xs 5 ) )
    ( nurl_print `index of 4:    ` ) ( nurl_println_int ( index_of xs 4 ) )
    ^ 0
}
