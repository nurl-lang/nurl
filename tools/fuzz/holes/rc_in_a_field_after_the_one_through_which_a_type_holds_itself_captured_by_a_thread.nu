// rc_in_a_field_after_the_one_through_which_a_type_holds_itself_captured_by_a_thread: `: Node { i val ( Vec Node ) kids ( Rc i ) tail }` holds itself through its second field and an `Rc` in its third; a `Node` is captured by a `thread_spawn` closure.
// main: refused — and so it stays: meeting `Node` again inside itself ends that path only, the fields after it are still read (the walk keeps a set of what it has asked, and a type met twice is not thereby answered).
// map: §6.5 | A3 | rejected | - | an `Rc` in the field after a type's self-reference, captured by a spawned closure: a cycle in the type ends one path of the derivation, not the derivation (agora #711)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Node { i val ( Vec Node ) kids ( Rc i ) tail }

@ look Node x → v {}

@ run sink Node x → v {
    ?? ( thread_spawn \ → v { ( look x ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
}

@ main → i { ^ 0 }
