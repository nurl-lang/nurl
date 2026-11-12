// rc_in_the_last_field_of_the_second_of_two_types_that_hold_each_other_captured_by_a_thread: `: Ping { i n ( Vec Pong ) ps }` and `: Pong { i m ?Ping back ( Rc i ) r }` hold each other, and the second ends in an `Rc`; a `Ping` is captured by a `thread_spawn` closure.
// main: refused — and so it stays: `Pong` reaches `Ping` again before its `Rc`, and the type already being asked about ends that path without answering for the fields that follow it.
// map: §6.5 | A3 | rejected | - | an `Rc` after the back edge of two types that hold each other, captured by a spawned closure: the derivation reads every field of every type in the cycle once (agora #711)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: Ping { i n ( Vec Pong ) ps }
: Pong { i m ? Ping back ( Rc i ) r }

@ look Ping x → v {}

@ run sink Ping x → v {
    ?? ( thread_spawn \ → v { ( look x ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
}

@ main → i { ^ 0 }
