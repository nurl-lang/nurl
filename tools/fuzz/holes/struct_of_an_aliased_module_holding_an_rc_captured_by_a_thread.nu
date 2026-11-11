// struct_of_an_aliased_module_holding_an_rc_captured_by_a_thread: a module's struct `Holder` holds an `Rc`; the program imports the module under the alias `hm`, so the type is spelled `hm__Holder`. A value of it is captured by a `thread_spawn` closure while the spawner keeps another share of the same `Rc`. Read "up to the first `__`" the type's base was `hm` — the alias, which names no type — so the rules that walk a type by its base found no fields and the `Rc` crossed unseen.
// main: accepted — both threads clone and drop one non-atomic count (ASan: heap-use-after-free). Behind an alias the base is the alias, the `__` after it and the module's own name (`__lty_base_end`; no alias is a type's name, `__import_alias_check`).
// map: §6.5 | A3 | rejected | - | a module's struct holding an Rc, imported under an alias (`hm__Holder`), captured by a spawned closure: the base of an aliased type's name is alias and name together (agora #639)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `compiler/tests/alias_rc_holder_mod.nu` hm

@ main → i {
    : ( Rc i ) r ( rc_new [i] 5 )
    : hm::Holder h2 @ hm::Holder { ( rc_clone [i] r ) }
    : hm::Holder h3 @ hm::Holder { ( rc_clone [i] r ) }
    ?? ( thread_spawn \ → v { ( hm::churn h3 20000 ) } ) {
        T t → { ( hm::churn h2 20000 ) ( thread_join t ) }
        F _ → {}
    }
    ^ - ( rc_strong [i] r ) 3
}
