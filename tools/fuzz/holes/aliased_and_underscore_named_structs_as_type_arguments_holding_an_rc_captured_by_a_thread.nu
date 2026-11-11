// aliased_and_underscore_named_structs_as_type_arguments_holding_an_rc_captured_by_a_thread: the two names whose base is more than "up to the first `__`" — a struct named `__Holder`, and a module's `Holder` behind the alias `hm` — as TYPE ARGUMENTS: `( Two hm::Holder __Holder )` is spelled `Two__hm__Holder____Holder`, and the walk that takes an instance apart into its arguments has to cut that spelling where the declarations did. Each holds a share of one `Rc`; the pair is captured by a `thread_spawn` closure while the spawner keeps a share.
// main: accepted — the arguments were cut at every `__`, so neither field's type was the struct holding the `Rc` (ASan: heap-use-after-free).
// map: §6.5 | A3 | rejected | - | `( Two hm::Holder __Holder )` captured by a spawned closure, each argument a struct holding an Rc: an instance's arguments are cut by the same base rule as its name (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `compiler/tests/alias_rc_holder_mod.nu` hm

: __Holder { ( Rc i ) r }

: Two [A B] { A a B b }

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : ( Two hm::Holder __Holder ) mine @ ( Two hm::Holder __Holder ) { @ hm::Holder { ( rc_clone [i] r ) } @ __Holder { ( rc_clone [i] r ) } }
    : ( Two hm::Holder __Holder ) theirs @ ( Two hm::Holder __Holder ) { @ hm::Holder { ( rc_clone [i] r ) } @ __Holder { ( rc_clone [i] r ) } }
    ?? ( thread_spawn \ → v { ( hm::churn . theirs a 20000 ) } ) {
        T t → { ( hm::churn . mine a 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 5
}
