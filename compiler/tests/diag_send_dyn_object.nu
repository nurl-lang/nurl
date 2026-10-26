// diag_send_dyn_object.nu — a trait object is not Send unless its trait
// says so. `%Peek`'s box holds whichever type implements `Peek`, and the
// object's type no longer says which: here a `Holder` whose Rc the
// spawner keeps a clone of. The derivation used to see `{ i8*, i8* }`,
// find no field to walk and answer Send, so the thread and the spawner
// changed one non-atomic count (agora #127, tools/fuzz/holes/h344). The
// message names the trait object and the promise that would let it cross.
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`

: Holder { ( Rc i ) r }

% Peek [T] { @ peek T self → i }

% Peek Holder { @ peek Holder h → i { ^ ( rc_get [i] . h r ) } }

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : %Peek d ( dyn Peek @ Holder { ( rc_clone [i] r ) } )
    ?? ( thread_spawn \ → v { ( nurl_print_int ( peek d ) ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
