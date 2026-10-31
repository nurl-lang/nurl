// dyn_object_carries_an_rc_to_a_thread: a trait object carried an Rc to another thread: `__thr_check` walks fields, payloads, generic arguments and aggregates, and a `%Churn` is `{ i8*, i8* }` with nothing it can see, so it answered Send for any boxed value. The thread's object and the spawner's `Holder` hold clones of one Rc, and both clone and drop it 64 at a time: the count's increments race, updates are lost, and the box is freed under a live clone.
// Closed: a trait object is Send only when its trait declares `: Send` (every impl is then checked to be Send), Sync only with `: Send Sync` (agora #127).
// v0.78.0: accepted; ASan reported heap-use-after-free or double-free on every run.
// map: §6.5 | A3 | rejected | h344 | a trait object boxing a struct with an Rc went into a thread closure while the spawner kept a clone: the Send/Sync derivation saw { i8*, i8* } and answered Send; a trait object is Send only when its trait declares : Send (Sync with : Send Sync), a promise each impl is held to
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

: Holder { ( Rc i ) r }

% Churn [T] { @ churn T self i n → i }

% Churn Holder {
    @ churn Holder h i n → i {
        : ~ i k 0
        ~ < k n {
            : ( Vec ( Rc i ) ) cs ( vec_new [( Rc i )] )
            : ~ i j 0
            ~ < j 64 { ( vec_push [( Rc i )] cs ( rc_clone [i] . h r ) ) = j + j 1 }
            = k + k 1
        }
        ^ ( rc_strong [i] . h r )
    }
}

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : Holder h2 @ Holder { ( rc_clone [i] r ) }
    : %Churn d ( dyn Churn @ Holder { ( rc_clone [i] r ) } )
    ?? ( thread_spawn \ → v { ( churn d 20000 ) } ) {
        T t → { ( churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 1
}
